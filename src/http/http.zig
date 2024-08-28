const std = @import("std");
const Algorithm = @import("Algorithm.zig").Algorithm;

pub const Server = struct {
    host: []const u8,
    port: u16,
};

pub const Http = struct {
    servers: []Server,
    method: ?[]const u8 = "round robin",

    pub fn httpSetup(self: *const Http) ?Algorithm {
        if (std.mem.eql(u8, self.method.?, "round robin")) {
            var RR = .{};
            return Algorithm{ .round_robin = &RR };
        }
        return null;
    }
};
