const std = @import("std");
const core = @import("core");

const utils = @import("../../../utils/utils.zig");

const Backend = @import("../../route.zig").Backend;
const Strategy = @import("../../Strategy.zig").Strategy;
const Config = @import("../../../config/config.zig").Config;
const MemoryRoute = @import("../../../shared_memory/RouteMemory.zig").MemoryRoute;

const ops = core.server_ops;
const Epoll = core.Epoll;
const ConnectionData = core.conn.ConnectionData;

const BackendData = struct {
    server: Backend,
    attempts: u32,
};

pub const RoundRobin = struct {
    backends: []BackendData = undefined,
    allocator: std.mem.Allocator = undefined,
    address: usize = undefined,
    memory_route: MemoryRoute = undefined,

    pub fn init(
        self: RoundRobin,
        servers: []Backend,
        allocator: std.mem.Allocator,
        path: []const u8,
        version: usize,
    ) !Strategy {
        _ = self;
        var backends = try allocator.alloc(BackendData, servers.len);

        for (servers, 0..) |value, i| {
            backends[i] = BackendData{ .server = value, .attempts = 0 };
        }

        const rr = RoundRobin{
            .backends = backends,
            .allocator = allocator,
            .memory_route = try MemoryRoute.read(path, version),
        };

        return Strategy{ .round_robin = rr };
    }

    pub fn deinit(self: RoundRobin) void {
        self.memory_route.close();
        self.allocator.free(self.backends);
    }

    pub fn handle(
        self: RoundRobin,
        conn: ConnectionData,
        request: []u8,
        response: []u8,
    ) !void {
        const servers_count = self.backends.len;
        var servers_down: usize = 0;
        var current_server_index: usize = undefined;
        var current_server: BackendData = undefined;
        const server_address: *usize = @ptrCast(self.memory_route.memory);

        while (servers_count > servers_down) {
            current_server_index = if (server_address.* >= self.backends.len) 0 else server_address.*;

            current_server = self.backends[current_server_index];
            if (current_server.attempts >= current_server.server.max_failure.?) {
                servers_down += 1;
                server_address.* = (current_server_index + 1) % servers_count;
                continue;
            }

            const backend_fd = ops.connectToBackend(current_server.server.host) catch {
                current_server.attempts += 1;
                servers_down += 1;
                server_address.* = (current_server_index + 1) % servers_count;
                continue;
            };

            // Forward request to backend
            ops.forwardRequestToBackend(backend_fd, request) catch {
                std.posix.close(backend_fd);
                current_server.attempts += 1;
                server_address.* = (current_server_index + 1) % servers_count;
                continue;
            };

            // Forward response back to client
            ops.forwardResponseToClient(backend_fd, conn, response) catch {
                std.posix.close(backend_fd);
                current_server.attempts += 1;
                server_address.* = (current_server_index + 1) % servers_count;
                continue;
            };

            // Reset attempts on successful connection
            if (current_server.attempts > 0) {
                current_server.attempts = 0;
            }

            // Successfully handled the request, find the next server
            server_address.* = (current_server_index + 1) % servers_count;
            return;
        }

        // No more valid servers
        try ops.sendBadGateway(conn);
        return;
    }
};
