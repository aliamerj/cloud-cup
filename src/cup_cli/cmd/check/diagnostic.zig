const std = @import("std");
const ops = @import("../../../http/server_operations.zig");

pub const Diagnostic = struct {
    host: []const u8,
    route: []const u8,
    is_healthy: bool,
    error_message: ?[]const u8,
    error_name: ?[]const u8,

    pub fn checkBackend(host: []const u8, route: []const u8) Diagnostic {
        var buffer: [1024]u8 = undefined;
        const backend_fd = ops.connectToBackend(host) catch |err| {
            const error_message = "Failed to connect to backend";

            return Diagnostic{
                .host = host,
                .route = route,
                .is_healthy = false,
                .error_message = error_message,
                .error_name = @errorName(err),
            };
        };
        defer std.posix.close(backend_fd);

        const check_request = std.fmt.bufPrint(&buffer, "GET / HTTP/1.1\r\nHost: {s}\r\nUser-Agent: curl/8.6.0\r\nAccept: */*\r\n\r\n", .{host}) catch |err| {
            const error_message = "Failed Making request";

            return Diagnostic{
                .host = host,
                .route = route,
                .is_healthy = false,
                .error_message = error_message,
                .error_name = @errorName(err),
            };
        };

        ops.forwardRequestToBackend(backend_fd, check_request) catch |err| {
            const error_message = "Failed to send health check request";

            return Diagnostic{
                .host = host,
                .route = route,
                .is_healthy = false,
                .error_message = error_message,
                .error_name = @errorName(err),
            };
        };
        var response_buffer: [1024]u8 = undefined;
        const res = ops.readClientRequest(.{ .ssl = null, .fd = backend_fd }, &response_buffer) catch |err| {
            const error_message = "Failed to read backend response";

            return Diagnostic{
                .host = host,
                .route = route,
                .is_healthy = false,
                .error_message = error_message,
                .error_name = @errorName(err),
            };
        };

        if (!std.mem.containsAtLeast(u8, res, 1, "200 OK")) {
            const error_message = "Backend responded with non-OK status";
            var parts = std.mem.split(u8, res, " ");

            _ = parts.next();
            const status_code_str = parts.next() orelse "";

            return Diagnostic{
                .host = host,
                .route = route,
                .is_healthy = false,
                .error_message = error_message,
                .error_name = status_code_str,
            };
        }

        return Diagnostic{
            .host = host,
            .route = route,
            .is_healthy = true,
            .error_message = null,
            .error_name = null,
        };
    }
};
