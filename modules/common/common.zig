pub const RouteMemory = @import("shared_memory/RouteMemory.zig");
pub const SharedConfig = @import("shared_memory/SharedMemory.zig").SharedMemory([4096]u8);

pub const Backend = struct {
    host: []const u8,
    max_failure: ?usize = 5,
};

test "test all" {
    _ = @import("shared_memory/RouteMemory.zig");
    _ = @import("shared_memory/SharedMemory.zig");
}
