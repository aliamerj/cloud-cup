const std = @import("std");
const cx = @import("connection.zig");
const ssl_ops = @import("ssl_ops.zig");
const http_ops = @import("http_ops.zig");

const Epoll = @import("epoll_handler.zig").Epoll;

const posix = std.posix;

const Connection = cx.Connection;
const ConnectionData = cx.ConnectionData;

pub fn acceptIncomingConnections(
    tcp_server: *std.net.Server,
    epoll: Epoll,
    ssl_ctx: ?*ssl_ops.SSL_CTX,
    connection: *Connection,
) !void {
    while (true) {
        const conn = tcp_server.accept() catch |err| {
            if (err == error.WouldBlock) break; // No more connections to accept
            return err;
        };
        const fd = conn.stream.handle;
        if (ssl_ctx) |_| {
            ssl_ops.acceptSSL(fd, epoll, ssl_ctx, connection) catch |err| {
                if (err == error.SSLHandshakeFailed or err == error.FailedToCreateSSLObject) {
                    try sendBadRequest(.{ .fd = conn.stream.handle, .ssl = null });
                    _ = std.posix.close(fd);
                    return;
                }
                return err;
            };
        } else {
            try http_ops.acceptHttp(fd, epoll, connection);
        }
    }
}

pub fn connectToBackend(host: []const u8) !posix.fd_t {
    const server_address = try parseServerAddress(host);
    const stream = try std.net.tcpConnectToAddress(server_address);
    return stream.handle;
}

pub fn readClientRequest(conn: ConnectionData, buffer: []u8) ![]u8 {
    if (conn.ssl) |s| {
        return try ssl_ops.readSSL(s, buffer);
    }
    return try http_ops.readHttp(conn.fd, buffer);
}

pub fn forwardRequestToBackend(backend_fd: posix.fd_t, request: []u8) !void {
    _ = try posix.send(backend_fd, request, 0);
}

pub fn forwardResponseToClient(backend_fd: posix.fd_t, conn: ConnectionData, response_buffer: []u8) !void {
    while (true) {
        const response_len = try posix.recv(backend_fd, response_buffer, 0);
        if (response_len == 0) break; // EOF reached

        if (conn.ssl) |s| {
            try ssl_ops.writeSSL(s, response_buffer, response_len);
        } else {
            try http_ops.writeHttp(conn.fd, response_buffer, response_len);
        }
    }

    // Clean up
    _ = std.posix.close(backend_fd);
}

pub fn closeConnection(epoll_fd: i32, conn: *ConnectionData, connection: *Connection) !void {
    if (conn.ssl) |s| {
        ssl_ops.closeConnection(s);
    }

    try std.posix.epoll_ctl(epoll_fd, std.os.linux.EPOLL.CTL_DEL, conn.fd, null);
    _ = std.posix.close(conn.fd);
    connection.destroy(conn);
}

pub fn sendBadGateway(conn: ConnectionData) !void {
    const response = "HTTP/1.1 502 Bad Gateway\r\nContent-Type: text/plain\r\nContent-Length: 20\r\n\r\n502 Bad Gateway here \n";
    if (conn.ssl) |s| {
        try ssl_ops.writeSSL(s, response, response.len);
        return;
    } else {
        try http_ops.writeHttp(conn.fd, response, response.len);
    }
}

pub fn sendBadRequest(conn: ConnectionData) !void {
    const response = "HTTP/1.1 400 Bad Request\r\n" ++
        "Content-Type: text/plain\r\n" ++
        "Content-Length: 53\r\n" ++
        "\r\n" ++
        "This server requires HTTPS. Please use HTTPS instead.\n";

    if (conn.ssl) |s| {
        try ssl_ops.writeSSL(s, response, response.len);
        return;
    } else {
        try http_ops.writeHttp(conn.fd, response, response.len);
    }
}

pub fn sendSecurityError(conn: ConnectionData, err: []const u8) !void {
    var response: []const u8 = "HTTP/1.1 400 Bad Request\r\nContent-Type: text/plain\r\nContent-Length: ";

    if (std.mem.eql(u8, err, "SQLInjection")) {
        response = "SQL Injection Detected: Request Blocked\r\n";
    } else if (std.mem.eql(u8, err, "XSS")) {
        response = "Cross-Site Scripting Detected: Request Blocked\r\n";
    } else if (std.mem.eql(u8, err, "DirectoryTraversal")) {
        response = "Directory Traversal Attempt Detected: Request Blocked\r\n";
    } else if (std.mem.eql(u8, err, "MissingRequiredHeaders")) {
        response = "Missing Required Headers: Request Blocked\r\n";
    }

    // Set the Content-Length header
    const content_length = response.len;
    var buf: [1024]u8 = undefined;
    response = std.fmt.bufPrint(&buf, "{s}{d}\r\n\r\n{s}", .{ "HTTP/1.1 400 Bad Request\r\nContent-Type: text/plain\r\nContent-Length: ", content_length, response }) catch {
        return error.OutOfMemory; // Handle memory allocation failure
    };

    if (conn.ssl) |s| {
        try ssl_ops.writeSSL(s, response, response.len);
    } else {
        try http_ops.writeHttp(conn.fd, response, response.len);
    }
}

fn parseServerAddress(input: []const u8) !std.net.Address {
    var split_iter = std.mem.splitSequence(u8, input, ":");
    const host = split_iter.next() orelse return error.InvalidHost;
    const port_str = split_iter.next() orelse null; // Use null if no port is specified

    var port: u16 = undefined;
    if (port_str != null) {
        port = try std.fmt.parseInt(u16, port_str.?, 10);
    } else {
        port = 80;
    }

    // Resolve the IP address or domain name
    const address_info = try std.net.Address.resolveIp(host, port);
    return address_info;
}

// test "acceptIncomingConnections handles incoming connections" {
//     const address_info = try std.net.Address.resolveIp("127.0.0.1", 3131);
//     var tcp_server = try address_info.listen(.{});

//     const epoll = try Epoll.init(tcp_server.stream.handle);
//     defer epoll.deinit();
//     var connection = Connection.init(std.testing.allocator);
//     defer connection.deinit();
//     // Call the function to test
//     try acceptIncomingConnections(&tcp_server, epoll, null, &connection);
//     try std.testing.expect(true);
// }
