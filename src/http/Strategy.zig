const std = @import("std");
const Server = @import("http.zig").Server;
const Round_robin = @import("strategies/round_robin.zig").RoundRobin;
const Epoll = @import("../utils/epoll.zig").Epoll;

pub const Strategy = union(enum) {
    round_robin: *Round_robin,

    pub fn init(self: Strategy, servers: []Server) !void {
        switch (self) {
            inline else => |algo| try algo.init(servers),
        }
    }

    pub fn handle(self: Strategy, server: *std.net.Server, epoll: Epoll) !void {
        switch (self) {
            inline else => |algo| try algo.handle(server, epoll),
        }
    }

    pub fn deinit(self: Strategy) void {
        switch (self) {
            inline else => |algo| algo.deinit(),
        }
    }
};
