const std = @import("std");
const Config = @import("../config/config.zig").Config;

pub fn setupCliSocket(config: Config) void {
    _ = config;
    const socket_path = "/tmp/cloud-cup.sock";
    std.posix.unlink(socket_path) catch {
        return;
    };

    var addr = std.net.Address.initUnix(socket_path) catch {
        return;
    };
    var uds_listener = addr.listen(.{
        .reuse_port = true,
        .reuse_address = true,
    }) catch {
        return;
    };
    defer uds_listener.deinit();

    std.log.info("UDS server listening on {s}", .{socket_path});

    while (true) {
        const client_conn = uds_listener.accept() catch {
            return;
        };
        defer client_conn.stream.close();

        // Read command from CLI
        var buffer: [256]u8 = undefined;
        const bytes_read = client_conn.stream.reader().read(&buffer) catch {
            return;
        };

        const command = buffer[0..bytes_read];

        // Process the command
        std.debug.print("Process command :{s}", .{command});
    }
}
