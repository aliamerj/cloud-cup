const std = @import("std");
const ops = @import("../../http/server_operations.zig");
const utils = @import("../../utils/utils.zig");

const Backend = @import("../route.zig").Backend;
const Strategy = @import("../Strategy.zig").Strategy;
const Epoll = @import("../../http/epoll_handler.zig").Epoll;
const Config = @import("../../config/config.zig").Config;
const ConnectionData = @import("../../http/connection.zig").ConnectionData;

const ServerData = struct {
    server: Backend,
    attempts: u32,
};

pub const Hash_map = std.AutoHashMap(usize, ServerData);

pub const RoundRobin = struct {
    backends: Hash_map = undefined,
    backend_key: usize = 0,

    pub fn init(self: RoundRobin, servers: []Backend, allocator: std.mem.Allocator) !Strategy {
        _ = self;
        var backends = Hash_map.init(allocator);

        for (servers, 0..) |value, i| {
            try backends.put(i, .{ .server = value, .attempts = 0 });
        }

        const rr = RoundRobin{
            .backends = backends,
            .backend_key = 0,
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
        const servers_count = backends.count();

        while (servers_count > servers_down.*) {
            if (backends.get(self.backend_key)) |server_to_run| {
                var current_server = server_to_run;

                if (current_server.attempts >= current_server.server.max_failure.?) {
                    servers_down.* += 1;
                    self.findNextServer(servers_count, strategy_hash, path);
                    continue;
                }

                const backend_fd = ops.connectToBackend(current_server.server.host) catch {
                    current_server.attempts += 1;
                    try self.backends.put(self.backend_key, current_server);
                    self.findNextServer(servers_count, strategy_hash, path);
                    continue;
                };

                // Forward request to backend
                ops.forwardRequestToBackend(backend_fd, request) catch {
                    std.posix.close(backend_fd);
                    current_server.attempts += 1;
                    try self.backends.put(self.backend_key, current_server);
                    self.findNextServer(servers_count, strategy_hash, path);
                    continue;
                };

                // Forward response back to client
                ops.forwardResponseToClient(backend_fd, conn, response) catch {
                    std.posix.close(backend_fd);
                    current_server.attempts += 1;
                    try self.backends.put(self.backend_key, current_server);
                    self.findNextServer(servers_count, strategy_hash, path);
                    continue;
                };

                // Reset attempts on successful connection
                if (current_server.attempts > 0) {
                    current_server.attempts = 0;
                    try self.backends.put(self.backend_key, current_server);
                }

                // Successfully handled the request, find the next server
                self.findNextServer(servers_count, strategy_hash, path);
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
        servers_number: usize,
        strategy_hash: *std.StringHashMap(Strategy),
        path: []const u8,
    ) void {
        // Move to the next server, wrapping around if necessary
        self.backend_key = (self.backend_key + 1) % servers_number;
        strategy_hash.put(path, .{ .round_robin = self.* }) catch unreachable;
    }
};
