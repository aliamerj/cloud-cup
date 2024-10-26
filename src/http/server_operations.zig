const std = @import("std");
const utils = @import("../utils/utils.zig");
const ssl = @import("../ssl/SSL.zig");
const cx = @import("../http/connection.zig");

const Epoll = @import("../http/epoll_handler.zig").Epoll;

const poxis = std.posix;

const Connection = cx.Connection;
const ConnectionData = cx.ConnectionData;

pub fn acceptIncomingConnections(tcp_server: std.net.Server, epoll: Epoll, ssl_ctx: ?*ssl.SSL_CTX, connection: Connection) !void {
    while (true) {
        const conn = @constCast(&tcp_server).accept() catch |err| {
            if (err == error.WouldBlock) break; // No more connections to accept
            return err;
        };

        const ssl_client = ssl.acceptSSLConnection(ssl_ctx, conn.stream.handle) catch |err| {
            if (err == error.SSLHandshakeFailed) {
                const new_connect = try @constCast(&connection).create(.{ .fd = conn.stream.handle, .ssl = null });
                try epoll.new(conn.stream.handle, new_connect);
                return;
            }
            return err;
        };
        const new_connect = try @constCast(&connection).create(.{ .fd = conn.stream.handle, .ssl = ssl_client });
        try epoll.new(conn.stream.handle, new_connect);
    }
}

pub fn connectToBackend(host: []const u8) !poxis.fd_t {
    const server_address = try utils.parseServerAddress(host);
    const stream = try std.net.tcpConnectToAddress(server_address);
    return stream.handle;
}

pub fn readClientRequest(conn: ConnectionData, buffer: []u8) ![]u8 {
    if (conn.ssl) |_| {
        return try ssl.readSSLRequest(conn.ssl, buffer);
    }

    const bytes_read = try std.posix.recv(conn.fd, buffer, 0);
    if (bytes_read <= 0) {
        return error.EmptyRequest;
    }

    return buffer[0..bytes_read];
}

pub fn forwardRequestToBackend(backend_fd: poxis.fd_t, request: []u8) !void {
    _ = try poxis.send(backend_fd, request, 0);
}

pub fn forwardResponseToClient(backend_fd: poxis.fd_t, conn: ConnectionData, response_buffer: []u8) !void {
    while (true) {
        const response_len = try poxis.recv(backend_fd, response_buffer, 0);
        if (response_len == 0) break; // EOF reached

        if (conn.ssl) |_| {
            try ssl.writeSSLResponse(conn.ssl, response_buffer, response_len);
        } else {
            _ = poxis.send(conn.fd, response_buffer[0..response_len], 0) catch |err| {
                if (err == error.BrokenPipe) {
                    std.log.warn("BrokenPipe occurred\n", .{});
                    return;
                }
                return err;
            };
        }
    }

    // Clean up
    _ = std.posix.close(backend_fd);
    if (conn.ssl) |_| {
        _ = ssl.shutdown(conn.ssl); // Only shut down SSL after entire response
    }
}
pub fn closeConnection(epoll_fd: i32, conn: ConnectionData, connection: Connection) !void {
    if (conn.ssl) |_| {
        ssl.closeConnection(conn.ssl);
    }

    @constCast(&connection).destroy(@constCast(&conn));
    try std.posix.epoll_ctl(epoll_fd, std.os.linux.EPOLL.CTL_DEL, conn.fd, null);
    _ = std.posix.close(conn.fd);
}

pub fn sendBadGateway(conn: ConnectionData) !void {
    const response = "HTTP/1.1 502 Bad Gateway\r\nContent-Type: text/plain\r\nContent-Length: 20\r\n\r\n502 Bad Gateway here \n";
    if (conn.ssl) |_| {
        try ssl.writeSSLResponse(conn.ssl, response, response.len);
        return;
    }

    _ = std.posix.send(conn.fd, response, 0) catch |err| {
        if (err == error.BrokenPipe) {
            std.log.warn("BrokenPipe occur \n", .{});
            return;
        }
        return err;
    };
}
