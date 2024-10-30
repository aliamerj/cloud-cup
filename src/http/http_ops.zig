const std = @import("std");
const Epoll = @import("../core/epoll/epoll_handler.zig").Epoll;
const Connection = @import("../core/connection/connection.zig").Connection;

pub fn acceptHttp(fd: std.posix.fd_t, epoll: Epoll, connection: Connection) !void {
    const new_connect = try @constCast(&connection).create(.{ .fd = fd, .ssl = null });
    try epoll.new(fd, new_connect);
}

pub fn readHttp(fd: std.posix.fd_t, buffer: []u8) ![]u8 {
    const bytes_read = try std.posix.recv(fd, buffer, 0);
    if (bytes_read <= 0) {
        return error.EmptyRequest;
    }

    return buffer[0..bytes_read];
}

pub fn writeHttp(fd: std.posix.fd_t, response_buffer: []const u8, response_len: usize) !void {
    _ = std.posix.send(fd, response_buffer[0..response_len], 0) catch |err| {
        if (err == error.BrokenPipe) {
            return;
        }
        return err;
    };
    return;
}
