const std = @import("std");

const Server = @import("../http.zig").Server;
const Epoll = @import("../../utils/epoll.zig").Epoll;
const ops = @import("../request.zig");

const ServerData = struct {
    server: Server,
    attempts: u32,
};

pub const Hash_map = std.AutoHashMap(usize, ServerData);

pub const RoundRobin = struct {
    const max_attempts: u32 = 5; // todo : add as an option to config file
    servers: Hash_map = undefined,

    pub fn init(self: *RoundRobin, servers: []Server) !void {
        self.servers = Hash_map.init(std.heap.page_allocator);
        for (servers, 0..) |value, i| {
            try self.servers.put(i, .{ .server = value, .attempts = 0 });
        }
    }

    pub fn deinit(self: *RoundRobin) void {
        self.servers.deinit();
    }

    pub fn handle(self: *RoundRobin, tcp_server: *std.net.Server, epoll: Epoll) !void {
        var events: [1024]std.os.linux.epoll_event = undefined;
        var server_key: usize = 0;
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        const allocator = gpa.allocator();
        defer _ = gpa.deinit();

        while (true) {
            const nfds = epoll.wait(&events);
            for (events[0..nfds]) |event| {
                if (event.data.fd == tcp_server.stream.handle) {
                    try acceptIncomingConnections(tcp_server, epoll);
                } else {
                    const client_fd = event.data.fd;
                    var servers_down: usize = 0;
                    try self.handleClientRequest(&servers_down, &server_key, client_fd, allocator);
                    _ = std.posix.close(client_fd);
                }
            }
        }
    }

    fn acceptIncomingConnections(tcp_server: *std.net.Server, epoll: Epoll) !void {
        while (true) {
            const conn = tcp_server.accept() catch |err| {
                if (err == error.WouldBlock) break; // No more connections to accept
                return err;
            };
            try epoll.new(conn.stream);
        }
    }

    fn handleClientRequest(self: *RoundRobin, servers_down: *usize, server_key: *usize, client_fd: std.os.linux.fd_t, allocator: std.mem.Allocator) !void {
        const servers_count = self.servers.count();

        const request_buffer = try allocator.alloc(u8, 4094);
        defer allocator.free(request_buffer);

        const request = ops.readClientRequest(client_fd, request_buffer) catch {
            try ops.sendBadGateway(client_fd);
            return;
        };

        while (servers_count > servers_down.*) {
            if (self.servers.get(server_key.*)) |server_to_run| {
                var current_server = server_to_run;
                if (current_server.attempts >= max_attempts) {
                    servers_down.* += 1;
                }

                const backend_fd = ops.connectToBackend(current_server.server.host, current_server.server.port);
                defer std.posix.close(backend_fd);

                if (backend_fd <= 0) {
                    current_server.attempts += 1;
                    try self.servers.put(server_key.*, current_server);
                    findNextServer(servers_count, server_key, current_server);
                    continue;
                }

                ops.forwardRequestToBackend(backend_fd, request) catch {
                    std.posix.close(backend_fd);
                    current_server.attempts += 1;
                    try self.servers.put(server_key.*, current_server);
                    findNextServer(servers_count, server_key, current_server);
                    continue;
                };

                const response_buffer = try allocator.alloc(u8, 4094);
                defer allocator.free(response_buffer);

                ops.forwardResponseToClient(backend_fd, client_fd, response_buffer) catch {
                    std.posix.close(backend_fd);
                    current_server.attempts += 1;
                    try self.servers.put(server_key.*, current_server);
                    findNextServer(servers_count, server_key, current_server);
                    continue;
                };

                if (current_server.attempts > 0) {
                    current_server.attempts = 0;
                    try self.servers.put(server_key.*, current_server);
                }
                findNextServer(servers_count, server_key, current_server);
                break;
            }
        }
        try ops.sendBadGateway(client_fd);
    }

    fn findNextServer(servers_number: usize, server_key: *usize, server_data: ServerData) void {
        // Skip the current server if its attempts have reached the max
        if (server_data.attempts >= max_attempts) {
            server_key.* = (server_key.* + 1) % servers_number;
            return;
        }
        // Move to the next server, wrapping around if necessary
        server_key.* = (server_key.* + 1) % servers_number;
    }
};
