const std = @import("std");
const config = @import("config.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    errdefer arena.deinit();
    const allocator = arena.allocator();
    const conf = try config.Config.init(allocator, "config/main_config.json");
    conf.run() catch |err| {
        std.debug.print("Failed to connect: {}\n", .{err});
        return;
    };
}
