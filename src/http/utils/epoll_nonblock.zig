const std = @import("std");

pub const EpollNonblock = struct {
    epoll_fd: i32,
    tcp: std.net.Server,
    clients: std.ArrayList(std.os.linux.fd_t),

    pub fn init(tcp: std.net.Server, allocator: std.mem.Allocator) !EpollNonblock {
        const clients = std.ArrayList(i32).init(allocator);
        const epoll_fd = try std.posix.epoll_create1(0);
        try setNonblock(tcp.stream);

        return EpollNonblock{
            .epoll_fd = epoll_fd,
            .tcp = tcp,
            .clients = clients,
        };
    }

    pub fn deinit(self: *EpollNonblock) void {
        _ = std.os.linux.close(self.epoll_fd);
        self.clients.deinit();
    }

    pub fn register(self: *EpollNonblock) !void {
        try self.clientRegister(self.tcp.stream.handle);
    }

    pub fn wait(self: *EpollNonblock, events: *[100]std.os.linux.epoll_event) usize {
        return std.posix.epoll_wait(self.epoll_fd, events, -1);
    }

    pub fn new(self: *EpollNonblock, stream: std.net.Stream) !void {
        const client_fd = stream.handle;
        try setNonblock(stream);
        try self.clients.append(client_fd);
        try self.clientRegister(client_fd);
    }

    fn setNonblock(conn: std.net.Stream) !void {
        var flags = try std.posix.fcntl(conn.handle, std.posix.F.GETFL, 0);
        var flags_s: *std.posix.O = @ptrCast(&flags);
        flags_s.NONBLOCK = true;
        _ = try std.posix.fcntl(conn.handle, std.posix.F.SETFL, flags);
    }

    fn clientRegister(self: *EpollNonblock, client_fd: i32) !void {
        var client_event = std.os.linux.epoll_event{
            .events = std.os.linux.EPOLL.IN | std.os.linux.EPOLL.ET,
            .data = .{ .fd = client_fd },
        };
        try std.posix.epoll_ctl(self.epoll_fd, std.os.linux.EPOLL.CTL_ADD, client_fd, &client_event);
    }
};
