const std = @import("std");

pub const Epoll = struct {
    epoll_fd: i32,

    pub fn init(tcp: std.net.Server) !Epoll {
        const epoll_fd = try std.posix.epoll_create1(0);
        try setNonblock(tcp.stream);
        std.log.info("Epoll initialized with server {d}", .{tcp.stream.handle});

        try registerEpoll(epoll_fd, tcp.stream.handle, true);

        return Epoll{
            .epoll_fd = epoll_fd,
        };
    }

    pub fn deinit(self: *const Epoll) void {
        _ = std.os.linux.close(self.epoll_fd);
    }

    pub fn wait(self: *const Epoll, events: *[100]std.os.linux.epoll_event) usize {
        return std.os.linux.epoll_wait(self.epoll_fd, events, 100, -1);
    }

    pub fn new(self: *const Epoll, stream: std.net.Stream) !void {
        const client_fd = stream.handle;
        try setNonblock(stream);
        try registerEpoll(self.epoll_fd, client_fd, false);
    }

    fn setNonblock(conn: std.net.Stream) !void {
        var flags = try std.posix.fcntl(conn.handle, std.posix.F.GETFL, 0);
        var flags_s: *std.posix.O = @ptrCast(&flags);
        flags_s.NONBLOCK = true;
        _ = try std.posix.fcntl(conn.handle, std.posix.F.SETFL, flags);
    }

    fn registerEpoll(epoll_fd: std.os.linux.fd_t, client_fd: i32, isNew: bool) !void {
        var client_event: std.os.linux.epoll_event = undefined;
        if (isNew) {
            client_event = std.os.linux.epoll_event{
                .events = std.os.linux.EPOLL.IN,
                .data = .{ .fd = client_fd },
            };
        } else {
            client_event = std.os.linux.epoll_event{
                .events = std.os.linux.EPOLL.IN | std.os.linux.EPOLL.ET,
                .data = .{ .fd = client_fd },
            };
        }

        try std.posix.epoll_ctl(epoll_fd, std.os.linux.EPOLL.CTL_ADD, client_fd, &client_event);
    }
};
