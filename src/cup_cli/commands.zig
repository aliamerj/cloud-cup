const std = @import("std");
const Config = @import("../config/config.zig").Config;
const Route = @import("../load_balancer/route.zig").Route;
const ops = @import("../http/server_operations.zig");
const Diagnostic = @import("cmd/check/diagnostic.zig").Diagnostic;

const convertToJSONConfig = @import("cmd/show/config.zig").convertToJSONConfig;

const Command = enum {
    ShowStatus,
    ShowConfig,
    Unknown,
    CheckAll,
};

pub fn processCLICommand(command: []u8, client_conn: std.net.Server.Connection, config: Config, allocator: std.mem.Allocator) !void {

    // Parse the command
    switch (parseCommand(command)) {
        .ShowStatus => {
            const response = "Cloud-Cup is running";
            _ = try client_conn.stream.writer().writeAll(response);
        },
        .ShowConfig => {
            const config_json = try convertToJSONConfig(config, allocator);
            defer config_json.deinit();
            _ = try client_conn.stream.writer().writeAll(config_json.items);
        },
        .CheckAll => {
            var diagnostices = std.ArrayList(Diagnostic).init(allocator);
            var string = std.ArrayList(u8).init(allocator);
            defer diagnostices.deinit();
            defer string.deinit();

            var routes = config.routes.iterator();
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
        .Unknown => {
            const response = "Unknown command";
            _ = try client_conn.stream.writer().writeAll(response);
        },
    }
}

fn parseCommand(command: []const u8) Command {
    if (std.mem.eql(u8, command, "show-status\n")) return Command.ShowStatus;
    if (std.mem.eql(u8, command, "show-config\n")) return Command.ShowConfig;
    if (std.mem.eql(u8, command, "check-all\n")) return Command.CheckAll;
    return Command.Unknown;
}
