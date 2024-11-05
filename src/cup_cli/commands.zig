const std = @import("std");
const Config = @import("../config/config.zig").Config;
const Diagnostic = @import("cmd/check/diagnostic.zig").Diagnostic;

const Shared_Memory = @import("../core/shared_memory/SharedMemory.zig").SharedMemory([4096]u8);

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
    shm: Shared_Memory,
    allocator: std.mem.Allocator,
) !void {
    // Parse the command and execute the corresponding action
    switch (parseCommand(command)) {
        .ShowStatus => try respondWithStatus(client_conn),
        .ShowConfig => try respondWithConfig(client_conn, shm),
        .CheckAll => try respondWithDiagnostics(client_conn, shm, allocator),
        .ApplyConfig => try applyNewConfig(client_conn, command, shm, allocator),
        .Unknown => try respondWithUnknownCommand(client_conn),
    }
}

fn parseCommand(command: []const u8) Command {
    if (std.mem.eql(u8, command, "show-status\n")) return Command.ShowStatus;
    if (std.mem.eql(u8, command, "show-config\n")) return Command.ShowConfig;
    if (std.mem.eql(u8, command, "check-all\n")) return Command.CheckAll;
    if (std.mem.startsWith(u8, command, "apply-config")) return Command.ApplyConfig;
    return Command.Unknown;
}

fn respondWithStatus(client_conn: std.net.Server.Connection) !void {
    const response = "Cloud-Cup is running";
    try client_conn.stream.writer().writeAll(response);
}

fn respondWithConfig(client_conn: std.net.Server.Connection, shm: Shared_Memory) !void {
    const shared_config = shm.readData();
    var parts = std.mem.split(u8, shared_config[0..], "|");
    _ = parts.next();
    const json = std.mem.trimRight(u8, parts.next().?, &[_]u8{ 0, '\n', '\r', ' ', '\t' });
    try client_conn.stream.writer().writeAll(json);
}

fn respondWithDiagnostics(
    client_conn: std.net.Server.Connection,
    shm: Shared_Memory,
    allocator: std.mem.Allocator,
) !void {
    var diagnostics = std.ArrayList(Diagnostic).init(allocator);
    var output = std.ArrayList(u8).init(allocator);
    defer diagnostics.deinit();
    defer output.deinit();

    const file_data = shm.readData();
    var parts = std.mem.split(u8, file_data[0..], "|");
    _ = parts.next();
    const json = std.mem.trimRight(u8, parts.next().?, &[_]u8{ 0, '\n', '\r', ' ', '\t' });

    var buffer: [4096]u8 = undefined;
    std.mem.copyForwards(u8, &buffer, json);

    var config = try Config.init(buffer[0..json.len], allocator, null);
    defer {
        config.conf.strategy_hash.deinit();
        config.deinitBuilder();
        config.config_parsed.deinit();
    }
    try gatherDiagnostics(&config, &diagnostics);

    try std.json.stringify(diagnostics.items, .{}, output.writer());
    try client_conn.stream.writer().writeAll(output.items);
}

fn gatherDiagnostics(config: *Config, diagnostics: *std.ArrayList(Diagnostic)) !void {
    var routes = config.conf.routes.iterator();
    while (routes.next()) |kv| {
        for (kv.value_ptr.backends) |backend| {
            const diagnostic = Diagnostic.checkBackend(backend.host, kv.key_ptr.*);
            try diagnostics.append(diagnostic);
        }
    }
}

fn applyNewConfig(
    client_conn: std.net.Server.Connection,
    command: []u8,
    shm: Shared_Memory,
    allocator: std.mem.Allocator,
) !void {
    var parts = std.mem.split(u8, command, "|");
    _ = parts.next();
    const file_path = parts.next();

    if (file_path == null) {
        try client_conn.stream.writer().writeAll("File path for new config required\n");
        return;
    }
    const config_path = std.mem.trim(u8, file_path.?, "\n");

    var buffer: [4096]u8 = undefined;
    const file_data = try loadConfigFile(config_path, &buffer);
    var config = Config.init(buffer[0..file_data.len], allocator, client_conn.stream.writer()) catch {
        return;
    };
    defer {
        config.conf.strategy_hash.deinit();
        config.deinitBuilder();
        config.config_parsed.deinit();
    }

    const config_version = try parseSharedConfigVersion(shm);
    try Config.share(shm, config_version + 1, buffer[0..file_data.len]);
    try client_conn.stream.writer().writeAll("New config applied successfully\n");
}

fn loadConfigFile(file_path: []const u8, buffer: *[4096]u8) ![]const u8 {
    return std.fs.cwd().readFile(file_path, buffer) catch |err| {
        var error_message: [128]u8 = undefined;
        const message = try std.fmt.bufPrint(&error_message, "Failed to load config '{s}': {s}", .{ file_path, @errorName(err) });
        return error_message[0..message.len];
    };
}

fn parseSharedConfigVersion(shm: Shared_Memory) !usize {
    const version_str = @constCast(&std.mem.split(u8, shm.readData()[0..], "|")).next().?;
    return std.fmt.parseInt(usize, version_str, 10);
}

fn respondWithUnknownCommand(client_conn: std.net.Server.Connection) !void {
    const response = "Unknown command\n";
    try client_conn.stream.writer().writeAll(response);
}
