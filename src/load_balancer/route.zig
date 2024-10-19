const std = @import("std");
const Strategy = @import("Strategy.zig").Strategy;

pub const Backend = struct {
    host: []const u8,
    max_failure: ?usize = 5,
};

pub const Route = struct {
    backends: []Backend,
    strategy: []const u8 = "round-robin", // default strategy

    pub fn routeSetup(self: *const Route) !Strategy {
        if (std.mem.eql(u8, self.strategy, "round-robin")) {
            return Strategy{ .round_robin = .{} };
        }

        std.log.err("Unsupported Strategy '{s}' by the current configuration.", .{
            self.strategy,
        });

        return error.UnsupportedStrategy;
    }
};
