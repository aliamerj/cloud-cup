const std = @import("std");
const Epoll = @import("epoll_handler.zig").Epoll;
const Connection = @import("connection.zig").Connection;

pub fn acceptHttp(fd: std.posix.fd_t, epoll: Epoll, connection: *Connection) !void {
    const new_connect = try connection.create(.{ .fd = fd, .ssl = null });
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

test "acceptHttp" {
    const allocator = std.testing.allocator;

    // Setup pipes and epoll
    const pipe = try std.posix.pipe();

    // Write to the pipe to trigger an event
    const msg = "hello";
    const result = try std.posix.write(pipe[1], msg);
    try std.testing.expect(result != 0);

    const epoll = try Epoll.init(pipe[0]);
    defer epoll.deinit();

    var connection = Connection.init(allocator);
    defer connection.deinit();

    // Simulate accepting a connection
    try acceptHttp(pipe[1], epoll, &connection);
    // Ensure the connection was added to the epoll
    var events: [1024]std.os.linux.epoll_event = undefined;
    const num_events = epoll.wait(&events);
    try std.testing.expect(num_events == 1);

    const event = events[0];
    try std.testing.expect(event.data.ptr > 0);

    // Remove the file descriptor
    try epoll.remove(pipe[0]);
    try epoll.remove(pipe[1]);

    // Cleanup
    _ = std.os.linux.close(pipe[0]);
    _ = std.os.linux.close(pipe[1]);
}
