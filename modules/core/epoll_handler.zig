const std = @import("std");
const Connection = @import("connection.zig").ConnectionData;

pub const Epoll = struct {
    epoll_fd: i32,

    pub fn init(fd: std.posix.fd_t) !Epoll {
        const epoll_fd = try std.posix.epoll_create1(0);
        try setNonblock(fd);

        var client_event: std.os.linux.epoll_event = .{
            .events = std.os.linux.EPOLL.IN,
            .data = .{ .fd = fd },
        };

        try std.posix.epoll_ctl(epoll_fd, std.os.linux.EPOLL.CTL_ADD, fd, &client_event);

        return Epoll{
            .epoll_fd = epoll_fd,
        };
    }

    pub fn deinit(self: *const Epoll) void {
        _ = std.os.linux.close(self.epoll_fd);
    }

    pub fn wait(self: *const Epoll, events: *[1024]std.os.linux.epoll_event) usize {
        return std.posix.epoll_wait(self.epoll_fd, events, -1);
    }

    pub fn new(self: *const Epoll, client_fd: std.posix.fd_t, conn: *Connection) !void {
        try setNonblock(client_fd);
        try registerEpoll(self.epoll_fd, client_fd, conn);
    }

    pub fn remove(self: *const Epoll, fd: std.posix.fd_t) !void {
        try std.posix.epoll_ctl(self.epoll_fd, std.os.linux.EPOLL.CTL_DEL, fd, null);
    }

    fn setNonblock(fd: std.posix.fd_t) !void {
        var flags = try std.posix.fcntl(fd, std.posix.F.GETFL, 0);
        var flags_s: *std.posix.O = @ptrCast(&flags);
        flags_s.NONBLOCK = true;
        _ = try std.posix.fcntl(fd, std.posix.F.SETFL, flags);
    }

    fn registerEpoll(epoll_fd: std.os.linux.fd_t, client_fd: i32, conn: *Connection) !void {
        var client_event: std.os.linux.epoll_event = .{
            .events = std.os.linux.EPOLL.IN | std.os.linux.EPOLL.ET,
            .data = .{ .ptr = @intFromPtr(conn) },
        };

        try std.posix.epoll_ctl(epoll_fd, std.os.linux.EPOLL.CTL_ADD, client_fd, &client_event);
    }
};

test "basic initialization and deinitialization" {

    // Create a dummy pipe for testing epoll
    const pipefds = try std.posix.pipe();

    const epoll = try Epoll.init(pipefds[0]);
    epoll.deinit();

    // Cleanup
    _ = std.os.linux.close(pipefds[0]);
    _ = std.os.linux.close(pipefds[1]);
}

test "add client to epoll" {
    const Conn = @import("connection.zig").Connection;

    // Create a dummy pipe for testing epoll
    const pipefds = try std.posix.pipe();

    const epoll = try Epoll.init(pipefds[0]);
    defer epoll.deinit();

    var connection = Conn.init(std.testing.allocator);
    const new_conn = try connection.create(.{ .fd = pipefds[1], .ssl = null });

    defer {
        connection.destroy(new_conn);
        connection.deinit();
    }

    // Add the write end of the pipe to epoll
    try epoll.new(pipefds[1], new_conn);

    try epoll.remove(new_conn.fd);

    // Cleanup
    _ = std.os.linux.close(pipefds[0]);
    _ = std.os.linux.close(pipefds[1]);
}

test "event wait on epoll" {
    const Conn = @import("connection.zig").Connection;
    const allocator = std.testing.allocator;

    // Create a dummy pipe for testing epoll
    const pipefds = try std.posix.pipe();

    const epoll = try Epoll.init(pipefds[0]);
    defer epoll.deinit();

    var connection = Conn.init(allocator);
    defer connection.deinit();

    const new_conn = try connection.create(.{ .fd = pipefds[1], .ssl = null });
    defer connection.destroy(new_conn);

    try epoll.new(pipefds[1], new_conn);

    // Write to the pipe to trigger an event
    const msg = "hello";
    const result = try std.posix.write(pipefds[1], msg);

    try std.testing.expect(result != 0);

    var events: [1024]std.os.linux.epoll_event = undefined;

    // Wait for the first event
    const num_events = epoll.wait(&events);
    try std.testing.expect(num_events == 1);

    const event = events[0];
    try std.testing.expect(event.data.ptr > 0);

    // Remove the file descriptor
    try epoll.remove(new_conn.fd);

    // Cleanup
    _ = std.os.linux.close(pipefds[0]);
    _ = std.os.linux.close(pipefds[1]);
}
test "multiple clients" {
    const Conn = @import("connection.zig").Connection;
    const allocator = std.testing.allocator;

    // Create two dummy pipes for testing epoll
    const pipe1 = try std.posix.pipe();
    const pipe2 = try std.posix.pipe();

    const epoll = try Epoll.init(pipe1[0]);
    defer epoll.deinit();

    var connection = Conn.init(allocator);
    defer connection.deinit();

    const connection1 = try connection.create(.{ .fd = pipe1[1], .ssl = null });
    defer connection.destroy(connection1);
    const connection2 = try connection.create(.{ .fd = pipe2[1], .ssl = null });
    defer connection.destroy(connection2);

    try epoll.new(pipe1[1], connection1);
    try epoll.new(pipe2[1], connection2);

    // Write to both pipes
    const result1 = try std.posix.write(pipe1[1], "test1");
    const result2 = try std.posix.write(pipe2[1], "test2");

    try std.testing.expect(result1 != 0 and result2 != 0);

    var events: [1024]std.os.linux.epoll_event = undefined;

    const num_events = epoll.wait(&events);

    try std.testing.expect(num_events == 1);
    try epoll.remove(connection1.fd);
    try epoll.remove(connection2.fd);

    // Cleanup
    _ = std.os.linux.close(pipe1[0]);
    _ = std.os.linux.close(pipe1[1]);
    _ = std.os.linux.close(pipe2[0]);
    _ = std.os.linux.close(pipe2[1]);
}
