const std = @import("std");
const Config = @import("../config/config.zig").Config;
const Config_Manager = @import("../config/config_managment.zig").Config_Manager;
const Diagnostic = @import("cmd/check/diagnostic.zig").Diagnostic;

const convertToJSONConfig = @import("cmd/show/config.zig").convertToJSONConfig;

const Command = enum {
    ShowStatus,
    ShowConfig,
    CheckAll,
    ApplyConfig,
    Unknown,
};

pub fn processCLICommand(
    command: []u8,
    client_conn: std.net.Server.Connection,
    config_manager: *Config_Manager,
    allocator: std.mem.Allocator,
) !void {

    // Parse the command
    switch (parseCommand(command)) {
        .ShowStatus => {
            const response = "Cloud-Cup is running";
            _ = try client_conn.stream.writer().writeAll(response);
        },
        .ShowConfig => {
            const config = config_manager.getCurrentConfig();
            const config_json = try convertToJSONConfig(config, allocator);
            defer config_json.deinit();
            _ = try client_conn.stream.writer().writeAll(config_json.items);
        },
        .CheckAll => {
            var diagnostices = std.ArrayList(Diagnostic).init(allocator);
            var string = std.ArrayList(u8).init(allocator);
            defer diagnostices.deinit();
            defer string.deinit();

            const config = config_manager.getCurrentConfig();

            var routes = config.conf.routes.iterator();
            while (routes.next()) |kv| {
                const backends = kv.value_ptr.backends;
                for (backends) |b| {
                    const backend = Diagnostic.checkBackend(b.host, kv.key_ptr.*);
                    try diagnostices.append(backend);
                }
            }

            try std.json.stringify(diagnostices.items, .{}, string.writer());
            _ = try client_conn.stream.writer().writeAll(string.items);
        },

        .ApplyConfig => {
            var parts = std.mem.split(u8, command, "|");
            _ = parts.next();
            const file_path = parts.next();

            if (file_path == null) {
                _ = try client_conn.stream.writer().writeAll("File path for new config required\n");
                return;
            }
            const config_path = std.mem.trim(u8, file_path.?, "\n");

            const config = config_manager.getCurrentConfig();

            const config_file = Config.readConfigFile(config_path, allocator) catch |err| {
                var buf: [1024]u8 = undefined;
                const err_message = try std.fmt.bufPrint(&buf, "Failed to load configuration file '{s}': {any}", .{ config_path, @errorName(err) });
                _ = try client_conn.stream.writer().writeAll(err_message);
                return;
            };

            var conf = Config.init(config_file, config.allocator);

            const err = try conf.applyConfig();
            if (err != null) {
                _ = try client_conn.stream.writer().writeAll(err.?.err_message);
                return;
            }

            try config_manager.pushNewConfig(conf);
            _ = try client_conn.stream.writer().writeAll("new config applied sucessfuly\n");
        },
        .Unknown => {
            const response = "Unknown command\n";
            _ = try client_conn.stream.writer().writeAll(response);
        },
    }
}

fn parseCommand(command: []const u8) Command {
    if (std.mem.eql(u8, command, "show-status\n")) return Command.ShowStatus;
    if (std.mem.eql(u8, command, "show-config\n")) return Command.ShowConfig;
    if (std.mem.eql(u8, command, "check-all\n")) return Command.CheckAll;
    if (std.mem.startsWith(u8, command, "apply-config")) return Command.ApplyConfig;
    return Command.Unknown;
}
