const std = @import("std");
const Config_Manager = @import("../config/config_managment.zig").Config_Manager;
const cmd = @import("commands.zig");
const setNonblock = @import("../utils/utils.zig").setNonblock;

pub fn setupCliSocket(
    config: *Config_Manager,
    allocator: *const std.mem.Allocator,
) void {
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
    var uds_listener = addr.listen(.{}) catch |err| {
        return std.debug.print("CLI Error: {any}\n", .{err});
    };
    defer uds_listener.deinit();

    setNonblock(uds_listener.stream.handle) catch |err| {
        return std.debug.print("CLI Error: {any}\n", .{err});
    };

    while (true) {
        const client_conn = uds_listener.accept() catch |err| {
            if (err == error.WouldBlock) {
                // No client connection, sleep to avoid busy-waiting
                std.time.sleep(100 * std.time.ns_per_ms); // Sleep for 100 ms
                continue;
            }
            return std.debug.print("CLI Error: {any}\n", .{err});
        };

        defer client_conn.stream.close();

        // Read command from CLI
        var buffer: [1024]u8 = undefined;
        const bytes_read = client_conn.stream.reader().read(&buffer) catch |err| {
            return std.debug.print("CLI Error: {any}\n", .{err});
        };

        cmd.processCLICommand(buffer[0..bytes_read], client_conn, config, allocator.*) catch |err| {
            return std.debug.print("CLI Error: {any}\n", .{err});
        };
    }
}
