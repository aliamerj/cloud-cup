const std = @import("std");
const ops = @import("../../../core/server_ops/server_ops.zig");
const utils = @import("../../../utils/utils.zig");

const Backend = @import("../../route.zig").Backend;
const Strategy = @import("../../Strategy.zig").Strategy;
const Epoll = @import("../../../core/epoll/epoll_handler.zig").Epoll;
const Config = @import("../../../config/config.zig").Config;
const ConnectionData = @import("../../../core/connection/connection.zig").ConnectionData;
const Backend_Manager = @import("backend_manager.zig").Backend_Manager;

const ServerData = struct {
    server: Backend,
    attempts: u32,
};

pub const RoundRobin = struct {
    backends: Backend_Manager = undefined,
    backend_ptr: ?*Backend_Manager.Backend = null,

    pub fn init(self: RoundRobin, servers: []Backend, allocator: std.mem.Allocator) !Strategy {
        _ = self;
        var bm = Backend_Manager.init(allocator);

        for (servers) |value| {
            try bm.push(.{ .server = value, .attempts = 0 });
        }

        const rr = RoundRobin{
            .backends = bm,
            .backend_ptr = bm.head,
        };

        return Strategy{ .round_robin = rr };
    }

    pub fn deinit(self: *RoundRobin) void {
        self.backends.deinit();
    }

    pub fn handle(
        self: *RoundRobin,
        conn: ConnectionData,
        request: []u8,
        response: []u8,
        config: Config,
        path: []const u8,
    ) !void {
        var servers_down: usize = 0;
        var strategy_hash = config.conf.strategy_hash;

        try self.handleClientRequest(
            &servers_down,
            conn,
            request,
            response,
            &strategy_hash,
            path,
        );
    }

    fn handleClientRequest(
        self: *RoundRobin,
        servers_down: *usize,
        conn: ConnectionData,
        request: []u8,
        response: []u8,
        strategy_hash: *std.StringHashMap(Strategy),
        path: []const u8,
    ) !void {
        const backends = strategy_hash.get(path).?.round_robin.backends;
        const servers_count = backends.len;

        while (servers_count > servers_down.*) {
            if (self.backend_ptr) |current_server| {
                if (current_server.data.attempts >= current_server.data.server.max_failure.?) {
                    servers_down.* += 1;
                    self.findNextServer(strategy_hash, path);
                    continue;
                }

                const backend_fd = ops.connectToBackend(current_server.data.server.host) catch {
                    current_server.data.attempts += 1;
                    self.findNextServer(strategy_hash, path);
                    continue;
                };

                // Forward request to backend
                ops.forwardRequestToBackend(backend_fd, request) catch {
                    std.posix.close(backend_fd);
                    current_server.data.attempts += 1;
                    self.findNextServer(strategy_hash, path);
                    continue;
                };

                // Forward response back to client
                ops.forwardResponseToClient(backend_fd, conn, response) catch {
                    std.posix.close(backend_fd);
                    current_server.data.attempts += 1;
                    self.findNextServer(strategy_hash, path);
                    continue;
                };

                // Reset attempts on successful connection
                if (current_server.data.attempts > 0) {
                    current_server.data.attempts = 0;
                }

                // Successfully handled the request, find the next server
                self.findNextServer(strategy_hash, path);
                return;
            }

            // No more valid servers
            try ops.sendBadGateway(conn);
            return;
        }

        // No backends available, return a 502 error
        try ops.sendBadGateway(conn);
    }
    fn findNextServer(
        self: *RoundRobin,
        strategy_hash: *std.StringHashMap(Strategy),
        path: []const u8,
    ) void {
        // Move to the next server, wrapping around if necessary
        self.backend_ptr = self.backend_ptr.?.next orelse self.backends.head;
        strategy_hash.put(path, .{ .round_robin = self.* }) catch unreachable;
    }
};
