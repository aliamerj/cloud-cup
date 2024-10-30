const std = @import("std");
const Epoll = @import("../core/epoll/epoll_handler.zig").Epoll;
const Connection = @import("../core/connection/connection.zig").Connection;
const ssl = @import("SSL.zig");

const posix = std.posix;

pub fn acceptSSL(fd: std.posix.fd_t, epoll: Epoll, ssl_ctx: ?*ssl.SSL_CTX, connection: Connection) !void {
    const ssl_client = ssl.acceptSSLConnection(ssl_ctx, fd) catch |err| {
        return err;
    };

    const new_connect = try @constCast(&connection).create(.{ .fd = fd, .ssl = ssl_client });
    try epoll.new(fd, new_connect);
}

pub fn readSSL(ssl_st: *ssl.SSL, buffer: []u8) ![]u8 {
    return try ssl.readSSLRequest(ssl_st, buffer);
}

pub fn writeSSL(ssl_st: *ssl.SSL, response_buffer: []const u8, response_len: usize) !void {
    return try ssl.writeSSLResponse(ssl_st, response_buffer, response_len);
}
