const std = @import("std");

const Command = enum {
    ShowStatus,
    Unknown,
};

pub fn processCLICommand(command: []u8, client_conn: std.net.Server.Connection) !void {
    // Parse the command
    switch (parseCommand(command)) {
        .ShowStatus => {
            const response = "Cloud-Cup is running";
            _ = try client_conn.stream.writer().writeAll(response);
        },
        else => {
            const response = "Unknown command";
            _ = try client_conn.stream.writer().writeAll(response);
        },
    }
}

fn parseCommand(command: []const u8) Command {
    if (std.mem.eql(u8, command, "show-status")) return Command.ShowStatus;
    return Command.Unknown;
}
