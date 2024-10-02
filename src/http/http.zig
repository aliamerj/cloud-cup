const std = @import("std");
const Strategy = @import("Strategy.zig").Strategy;

pub const Server = struct {
    host: []const u8,
    port: u16,
    max_failure: ?usize = 5,
};

pub const Http = struct {
    servers: []Server,
    strategy: ?[]const u8 = "round robin",

    pub fn httpSetup(self: *const Http) ?Strategy {
        if (std.mem.eql(u8, self.strategy.?, "round robin")) {
            var round_robin = .{};
            return Strategy{ .round_robin = &round_robin };
        }
        return null;
    }
};
