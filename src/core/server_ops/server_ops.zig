const std = @import("std");
const utils = @import("../../utils/utils.zig");
const cx = @import("../../core//connection/connection.zig");
const ssl = @import("../../ssl/SSL.zig");
const Epoll = @import("../../core/epoll/epoll_handler.zig").Epoll;

const ssl_ops = @import("../../ssl/ssl_ops.zig");
const http_ops = @import("../../http/http_ops.zig");

const posix = std.posix;

const Connection = cx.Connection;
const ConnectionData = cx.ConnectionData;

pub fn acceptIncomingConnections(tcp_server: std.net.Server, epoll: Epoll, ssl_ctx: ?*ssl.SSL_CTX, connection: Connection) !void {
    while (true) {
        const conn = @constCast(&tcp_server).accept() catch |err| {
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
    const server_address = try utils.parseServerAddress(host);
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
    if (conn.ssl) |s| {
        _ = ssl.shutdown(s); // Only shut down SSL after entire response
    }
}

pub fn closeConnection(epoll_fd: i32, conn: ConnectionData, connection: Connection) !void {
    if (conn.ssl) |s| {
        ssl.closeConnection(s);
    }

    @constCast(&connection).destroy(@constCast(&conn));
    try std.posix.epoll_ctl(epoll_fd, std.os.linux.EPOLL.CTL_DEL, conn.fd, null);
    _ = std.posix.close(conn.fd);
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
