const std = @import("std");

const Server = @import("../http.zig").Server;
const Epoll = @import("../../utils/epoll.zig").Epoll;

const ServerData = struct {
    server: Server,
    attempts: u32,
};

pub const Hash_map = std.AutoHashMap(usize, ServerData);

pub const RoundRobin = struct {
    const max_attempts: u32 = 5;
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
        var events: [100]std.os.linux.epoll_event = undefined;
        var server_key: usize = 0;

        while (true) {
            const nfds = epoll.wait(&events);
            for (events[0..nfds]) |event| {
                if (event.data.fd == tcp_server.stream.handle) {
                    try acceptIncomingConnections(tcp_server, epoll);
                } else {
                    const client_fd = event.data.fd;
                    var servers_down: usize = 0;
                    // Read the client request
                    var buffer: [1024]u8 = undefined;
                    const bytes_read = try std.posix.read(client_fd, &buffer);
                    if (bytes_read <= 0) {
                        std.posix.close(client_fd);
                        continue;
                    }

                    try self.handleClientRequest(&servers_down, buffer[0..bytes_read], &server_key, client_fd);
                    _ = std.posix.close(event.data.fd);
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
            std.log.info("Accepted client connection: {d}", .{conn.stream.handle});
        }
    }

    fn handleClientRequest(self: *RoundRobin, servers_down: *usize, request: []u8, server_key: *usize, client_fd: std.os.linux.fd_t) !void {
        const servers_count = self.servers.count();

        while (servers_count > servers_down.*) {
            if (self.servers.get(server_key.*)) |server_to_run| {
                var current_server = server_to_run;
                if (current_server.attempts >= max_attempts) {
                    servers_down.* += 1;
                }
                connectAndForwardRequest(current_server.server, request, client_fd) catch {
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
        try self.sendBadGateway(client_fd);
    }

    fn connectAndForwardRequest(backend: Server, request: []u8, client_fd: std.os.linux.fd_t) !void {
        const backend_sock = try createSocket(backend.host, backend.port);
        defer backend_sock.close();
        try sendRequest(backend_sock, request);
        try forwardResponse(backend_sock, client_fd);
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

    fn sendBadGateway(self: *RoundRobin, client_fd: i32) !void {
        _ = self;
        const response = "HTTP/1.1 502 Bad Gateway\r\nContent-Type: text/plain\r\nContent-Length: 16\r\n\r\n502 Bad Gateway\n";
        _ = try std.posix.write(client_fd, response);
    }

    fn createSocket(host: []const u8, port: u16) !std.net.Stream {
        const address = try std.net.Address.parseIp4(host, port);
        return try std.net.tcpConnectToAddress(address);
    }

    fn sendRequest(backend_sock: std.net.Stream, request: []const u8) !void {
        try backend_sock.writer().writeAll(request);
    }

    fn forwardResponse(backend_sock: std.net.Stream, client_fd: i32) !void {
        var response_buffer: [8192]u8 = undefined;
        while (true) {
            const response_len = try backend_sock.reader().read(&response_buffer);
            if (response_len == 0) break; // EOF reached

            _ = std.os.linux.write(client_fd, response_buffer[0..response_len].ptr, response_len);
        }
    }
};
