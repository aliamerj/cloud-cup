const std = @import("std");
const Backend = @import("route.zig").Backend;
const Round_robin = @import("strategies/round_robin.zig").RoundRobin;
const Config = @import("../config/config.zig").Config;

pub const Strategy = union(enum) {
    round_robin: Round_robin,

    pub fn init(self: Strategy, servers: []Backend, allocator: std.mem.Allocator) !Strategy {
        switch (self) {
            inline else => |strategy| return try strategy.init(servers, allocator),
        }
    }

    pub fn handle(
        self: *Strategy,
        client_fd: std.posix.fd_t,
        request: []u8,
        response: []u8,
        config: Config,
        path: []const u8,
    ) !void {
        switch (self.*) {
            inline else => |strategy| {
                var stra = @constCast(&strategy);
                try stra.handle(client_fd, request, response, config, path);
            },
        }
    }

    pub fn deinit(self: *Strategy) void {
        switch (self.*) {
            inline else => |strategy| {
                var stra = @constCast(&strategy);
                stra.deinit();
            },
        }
    }
};
