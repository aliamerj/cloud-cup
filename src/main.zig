const builtin = @import("builtin");
const std = @import("std");
const SharedConfig = @import("common").SharedConfig;
const configuration = @import("config");
const Server = @import("server.zig").Server;

const Config = configuration.Config;
const ConfigManager = configuration.ConfigManager;

pub fn main() !void {
    if (builtin.os.tag != .linux) {
        std.log.err("This application only supports Linux.", .{});
        return;
    }
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Retrieve and parse command-line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.log.err("Usage: {s} <config_file_path>", .{args[0]});
        return;
    }

    const config_path = args[1];
    var file_buffer: [4096]u8 = undefined;
    const file_data = std.fs.cwd().readFile(config_path, &file_buffer) catch |err| {
        std.log.err("Failed to load configuration file '{s}': {any}", .{ config_path, err });
        return;
    };

    var mutex = std.Thread.Mutex{};
    var shared_config = try SharedConfig.init(file_buffer, &mutex);
    defer shared_config.deinit();

    var config = Config.init(file_data, allocator, null, 1, true) catch |err| {
        std.log.err("Config error: {s}\n", .{@errorName(err)});
        return;
    };

    defer config.deinit();

    var config_manager = ConfigManager.init(allocator);
    defer config_manager.deinit();
    try config_manager.pushNewConfig(config);

    try Config.share(shared_config, 1, file_data);

    try Server.run(&config_manager, shared_config);
}

test "test all" {
    _ = @import("server.zig");
    _ = @import("worker.zig");
    _ = @import("cup_cli/cup_cli.zig");
}
