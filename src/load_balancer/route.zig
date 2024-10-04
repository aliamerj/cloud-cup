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

        std.log.err("Unsupported load balancing Strategy: '{s}'. The method '{s}' is not supported by the current load balancer configuration.", .{
            self.strategy,
            self.strategy,
        });

        return error.Unsupported;
    }
};
