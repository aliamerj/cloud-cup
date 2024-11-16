const std = @import("std");

const Config = @import("config/config.zig").Config;
const Shared_Config = @import("core/shared_memory/SharedMemory.zig").SharedMemory([4096]u8);
const Config_Manager = @import("config/config_managment.zig").Config_Manager;
const Server = @import("server.zig").Server;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var file_buffer: [4096]u8 = undefined;
    const file_data = std.fs.cwd().readFile("config/main_config.json", &file_buffer) catch |err| {
        std.log.err("Failed to load configuration file 'config/main_config.json': {any}", .{err});
        return;
    };

    var mutex = std.Thread.Mutex{};
    var shared_config = try Shared_Config.init(file_buffer, &mutex);
    defer shared_config.deinit();

    var config = Config.init(file_data, allocator, null, 1, true) catch |err| {
        std.log.err("Config error: {s}\n", .{@errorName(err)});
        return;
    };

    defer {
        config.deinitMemory();
        config.deinit();
    }

    var config_manager = Config_Manager.init(allocator);
    defer config_manager.deinit();
    try config_manager.pushNewConfig(config);

    try Config.share(shared_config, 1, file_data);

    try Server.run(&config_manager, shared_config);
}
