const std = @import("std");
const cmd = @import("commands.zig");
const configuration = @import("config");
const SharedConfig = @import("common").SharedConfig;

const Config = configuration.Config;

pub fn setupCliSocket(
    shm: SharedConfig,
) void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

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

        cmd.processCLICommand(buffer[0..bytes_read], client_conn, shm, allocator) catch |err| {
            return std.debug.print("CLI Error: {any}\n", .{err});
        };
    }
}

fn setNonblock(fd: std.posix.fd_t) !void {
    var flags = try std.posix.fcntl(fd, std.posix.F.GETFL, 0);
    var flags_s: *std.posix.O = @ptrCast(&flags);
    flags_s.NONBLOCK = true;
    _ = try std.posix.fcntl(fd, std.posix.F.SETFL, flags);
}

test "test cli commands" {
    _ = @import("cmd/apply/apply_new_config.zig");
    _ = @import("cmd/show/show_config.zig");
    _ = @import("cmd/check/check_ops.zig");
}
