const std = @import("std");
const Connection = @import("connection.zig").ConnectionData;

pub const Epoll = struct {
    epoll_fd: i32,

    pub fn init(tcp: std.net.Server) !Epoll {
        const epoll_fd = try std.posix.epoll_create1(0);
        try setNonblock(tcp.stream.handle);

        var client_event: std.os.linux.epoll_event = .{
            .events = std.os.linux.EPOLL.IN | std.os.linux.EPOLL.OUT | std.os.linux.EPOLL.ET,
            .data = .{ .fd = tcp.stream.handle },
        };

        try std.posix.epoll_ctl(epoll_fd, std.os.linux.EPOLL.CTL_ADD, tcp.stream.handle, &client_event);

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

    fn setNonblock(fd: std.posix.fd_t) !void {
        var flags = try std.posix.fcntl(fd, std.posix.F.GETFL, 0);
        var flags_s: *std.posix.O = @ptrCast(&flags);
        flags_s.NONBLOCK = true;
        _ = try std.posix.fcntl(fd, std.posix.F.SETFL, flags);
    }

    fn registerEpoll(epoll_fd: std.os.linux.fd_t, client_fd: i32, conn: *Connection) !void {
        var client_event: std.os.linux.epoll_event = .{
            .events = std.os.linux.EPOLL.IN | std.os.linux.EPOLL.OUT | std.os.linux.EPOLL.ET,
            .data = .{ .ptr = @intFromPtr(conn) },
        };

        try std.posix.epoll_ctl(epoll_fd, std.os.linux.EPOLL.CTL_ADD, client_fd, &client_event);
    }
};
