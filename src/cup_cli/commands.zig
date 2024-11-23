const std = @import("std");
const configuration = @import("config");
const SharedConfig = @import("common").SharedConfig;
const Config = configuration.Config;

const respondWithDiagnostics = @import("cmd/check/check_ops.zig").respondWithDiagnostics;
const respondWithConfig = @import("cmd/show/show_config.zig").respondWithConfig;
const applyNewConfig = @import("cmd/apply/apply_new_config.zig").applyNewConfig;

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
    shm: SharedConfig,
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

fn respondWithUnknownCommand(client_conn: std.net.Server.Connection) !void {
    const response = "Unknown command\n";
    try client_conn.stream.writer().writeAll(response);
}
