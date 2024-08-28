const std = @import("std");
const config = @import("config.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const conf = try config.Config.init("config/main_config.json", allocator);
    conf.run() catch |err| {
        std.debug.print("Failed to connect: {}\n", .{err});
        return;
    };
}
