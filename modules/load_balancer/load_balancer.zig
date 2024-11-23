const std = @import("std");
const Backend = @import("common").Backend;
const Roundrobin = @import("round_robin.zig").RoundRobin;
const ConnectionData = @import("core").conn.ConnectionData;

pub const Strategy = union(enum) {
    round_robin: Roundrobin,

    pub fn init(
        self: Strategy,
        servers: []Backend,
        allocator: std.mem.Allocator,
        path: []const u8,
        version: usize,
    ) !Strategy {
        switch (self) {
            inline else => |strategy| return try strategy.init(servers, allocator, path, version),
        }
    }

    pub fn handle(
        self: Strategy,
        conn: ConnectionData,
        request: []u8,
        response: []u8,
    ) !void {
        switch (self) {
            inline else => |strategy| {
                try strategy.handle(conn, request, response);
            },
        }
    }

    pub fn deinit(self: Strategy) void {
        switch (self) {
            inline else => |strategy| {
                strategy.deinit();
            },
        }
    }
};
