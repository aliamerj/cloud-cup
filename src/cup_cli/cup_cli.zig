const std = @import("std");
const Config = @import("../config/config.zig").Config;
const cmd = @import("commands.zig");

pub fn setupCliSocket(config: Config) void {
    _ = config;
    const socket_path = "/tmp/cloud-cup.sock";

    // Ensure the socket file does not already exist
    std.posix.unlink(socket_path) catch |err| {
        if (err != error.FileNotFound) {
            return std.debug.print("CLI Error: {any}\n", .{err});
        }
    };

    // Set up the Unix Domain Socket
    var addr = std.net.Address.initUnix(socket_path) catch |err| {
        return std.debug.print("CLI Error: {any}\n", .{err});
    };

    // Listen on the Unix socket
    var uds_listener = addr.listen(.{
        .reuse_port = true,
        .reuse_address = true,
    }) catch |err| {
        return std.debug.print("CLI Error: {any}\n", .{err});
    };
    defer uds_listener.deinit();

    while (true) {
        // Accept a new connection from the client (CLI in this case)
        const client_conn = uds_listener.accept() catch |err| {
            return std.debug.print("CLI Error: {any}\n", .{err});
        };
        defer client_conn.stream.close();

        // Read command from CLI
        var buffer: [256]u8 = undefined;
        const bytes_read = client_conn.stream.reader().read(&buffer) catch |err| {
            return std.debug.print("CLI Error: {any}\n", .{err});
        };

        cmd.processCLICommand(buffer[0..bytes_read], client_conn) catch |err| {
            return std.debug.print("CLI Error: {any}\n", .{err});
        };
    }
}
