const std = @import("std");
const Config = @import("config/config.zig").Config;
const Server = @import("server.zig").Server;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var conf = Config.init("config/main_config.json", allocator) catch |err| {
        std.log.err("Failed to load configuration file 'config/main_config.json': {any}", .{err});
        return;
    };
    defer conf.deinitBuilder();

    var server = Server.init(conf);
    try server.run();
}
