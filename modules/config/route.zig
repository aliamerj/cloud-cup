const std = @import("std");
const Backend = @import("common").Backend;
const Strategy = @import("loadBalancer").Strategy;

pub const strategies_supported = [_][]const u8{"round-robin"};

pub const Route = struct {
    backends: []Backend,
    strategy: []const u8 = "round-robin", // default strategy

    pub fn routeSetup(self: *const Route) Strategy {
        if (std.mem.eql(u8, self.strategy, strategies_supported[0])) {
            return Strategy{ .round_robin = .{} };
        }
        unreachable;
    }
};

test "Route - Setup Strategy" {
    var backends: [1]Backend = .{
        .{
            .host = "127.0.0.1",
            .max_failure = 3,
        },
    };

    const route = Route{
        .backends = &backends,
        .strategy = "round-robin",
    };

    const strategy = route.routeSetup();

    // Validate that the `round_robin` field in Strategy is active
    const is_round_robin_active = switch (strategy) {
        .round_robin => true,
        //  else => false,
    };

    try std.testing.expect(is_round_robin_active);
}
