const std = @import("std");
const Server = @import("http.zig").Server;
const Round_robin = @import("strategies/round_robin.zig").RoundRobin;
const Epoll = @import("../utils/epoll.zig").Epoll;

pub const Strategy = union(enum) {
    round_robin: *Round_robin,

    pub fn handle(self: Strategy, server: *std.net.Server, epoll: Epoll, servers: []Server, allocator: std.mem.Allocator) !void {
        switch (self) {
            inline else => |strategy| try strategy.handle(server, epoll, servers, allocator),
        }
    }
};
