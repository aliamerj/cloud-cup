const std = @import("std");
const Server = @import("http.zig").Server;

const Round_robin = @import("methods/round_robin.zig").RoundRobin;

pub const Algorithm = union(enum) {
    round_robin: *Round_robin,

    pub fn init(self: Algorithm, servers: []Server) !void {
        switch (self) {
            inline else => |algo| try algo.init(servers),
        }
    }

    pub fn handle(self: Algorithm, request: *const []u8, response_writer: *const std.net.Stream.Writer) !void {
        switch (self) {
            inline else => |algo| try algo.handle(request, response_writer),
        }
    }

    pub fn deinit(self: Algorithm) void {
        switch (self) {
            inline else => |algo| algo.deinit(),
        }
    }
};
