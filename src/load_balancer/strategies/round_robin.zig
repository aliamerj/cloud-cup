const std = @import("std");

const Backend = @import("../route.zig").Backend;
const Strategy = @import("../Strategy.zig").Strategy;
const Epoll = @import("../../http/epoll_handler.zig").Epoll;
const ops = @import("../../http/server_operations.zig");
const utils = @import("../../utils/utils.zig");

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

    pub fn handle(self: *RoundRobin, client_fd: std.posix.fd_t, allocator: std.mem.Allocator) !void {
        var servers_down: usize = 0;
        try self.handleClientRequest(&servers_down, client_fd, allocator);
    }

    fn handleClientRequest(self: *RoundRobin, servers_down: *usize, client_fd: std.posix.fd_t, allocator: std.mem.Allocator) !void {
        const servers_count = self.backends.count();

        const request_buffer = try allocator.alloc(u8, 4094);
        defer allocator.free(request_buffer);

        const request = ops.readClientRequest(client_fd, request_buffer) catch {
            try ops.sendBadGateway(client_fd);
            return;
        };
        std.debug.print("request {s}\n", .{request});

        while (servers_count > servers_down.*) {
            if (self.backends.get(self.backend_key)) |server_to_run| {
                var current_server = server_to_run;
                if (current_server.attempts >= current_server.server.max_failure.?) {
                    servers_down.* += 1;
                }

                const backend_fd = ops.connectToBackend(try utils.parseServerAddress(current_server.server.host));

                if (backend_fd <= 0) {
                    current_server.attempts += 1;
                    try self.backends.put(self.backend_key, current_server);
                    self.findNextServer(servers_count);
                    continue;
                }
                defer std.posix.close(backend_fd);

                ops.forwardRequestToBackend(backend_fd, request) catch {
                    std.posix.close(backend_fd);
                    current_server.attempts += 1;
                    try self.backends.put(self.backend_key, current_server);
                    self.findNextServer(servers_count);
                    continue;
                };

                const response_buffer = try allocator.alloc(u8, 4094);
                defer allocator.free(response_buffer);

                ops.forwardResponseToClient(backend_fd, client_fd, response_buffer) catch {
                    std.posix.close(backend_fd);
                    current_server.attempts += 1;
                    try self.backends.put(self.backend_key, current_server);
                    self.findNextServer(servers_count);
                    continue;
                };

                if (current_server.attempts > 0) {
                    current_server.attempts = 0;
                    try self.backends.put(self.backend_key, current_server);
                }
                self.findNextServer(servers_count);
                break;
            }
        }
        try ops.sendBadGateway(client_fd);
    }

    fn findNextServer(self: *RoundRobin, servers_number: usize) void {

        // Move to the next server, wrapping around if necessary
        self.backend_key = (self.backend_key + 1) % servers_number;
    }
};
