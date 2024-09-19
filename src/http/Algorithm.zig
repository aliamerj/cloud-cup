const std = @import("std");
const Server = @import("http.zig").Server;

const Round_robin = @import("methods/round_robin.zig").RoundRobin;
const EpollNonblock = @import("utils/epoll_nonblock.zig").EpollNonblock;
pub const Algorithm = union(enum) {
    round_robin: *Round_robin,

    pub fn init(self: Algorithm, servers: []Server) !void {
        switch (self) {
            inline else => |algo| try algo.init(servers),
        }
    }

    pub fn handle(self: Algorithm, server: *std.net.Server, epoll: *EpollNonblock) !void {
        switch (self) {
            inline else => |algo| try algo.handle(server, epoll),
        }
    }

    pub fn deinit(self: Algorithm) void {
        switch (self) {
            inline else => |algo| algo.deinit(),
        }
    }
};
