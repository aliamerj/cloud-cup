const std = @import("std");

const Server = @import("../http.zig").Server;

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

    pub fn handle(self: *RoundRobin, server: *std.net.Server) !void {
        var server_key: usize = 0;
        const servers_number = self.servers.count();

        while (true) {
            var servers_down: usize = 0;
            const client = try server.accept();
            defer client.stream.close();

            const client_writer = client.stream.writer();
            const client_reader = client.stream.reader();

            // Read the HTTP request
            var request_buffer: [8192]u8 = undefined;
            const request_len = try client_reader.read(&request_buffer);

            while (servers_number > servers_down) {
                if (self.servers.get(server_key)) |server_to_run| {
                    var current_server = server_to_run;
                    if (current_server.attempts >= max_attempts) {
                        servers_down += 1;
                    }
                    connectAndForwardRequest(current_server.server, &request_buffer[0..request_len], &client_writer) catch {
                        current_server.attempts += 1;
                        try self.servers.put(server_key, current_server);
                        findNextServer(servers_number, &server_key, current_server);
                        continue;
                    };

                    if (current_server.attempts > 0) {
                        current_server.attempts = 0;
                        try self.servers.put(server_key, current_server);
                    }
                    findNextServer(servers_number, &server_key, current_server);
                    break;
                }
            }
            try self.sendBadGateway(&client_writer);
        }
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

    fn sendBadGateway(self: *RoundRobin, response_writer: *const std.net.Stream.Writer) !void {
        _ = self;
        const response = "HTTP/1.1 502 Bad Gateway\r\nContent-Type: text/plain\r\nContent-Length: 16\r\n\r\n502 Bad Gateway\n";
        try response_writer.writeAll(response);
    }

    fn connectAndForwardRequest(server: Server, request: *const []u8, response_writer: *const std.net.Stream.Writer) !void {
        const socket = try createSocket(server.host, server.port);
        defer socket.close();

        try sendRequest(socket, request);
        try forwardResponse(socket, response_writer);
    }

    fn createSocket(host: []const u8, port: u16) !std.net.Stream {
        const address = try std.net.Address.parseIp4(host, port);
        return try std.net.tcpConnectToAddress(address);
    }

    fn sendRequest(socket: std.net.Stream, request: *const []u8) !void {
        try socket.writer().writeAll(request.*);
    }

    fn forwardResponse(socket: std.net.Stream, response_writer: *const std.net.Stream.Writer) !void {
        var response_buffer: [8192]u8 = undefined;
        while (true) {
            const response_len = try socket.reader().read(&response_buffer);
            if (response_len == 0) break;
            try response_writer.writeAll(response_buffer[0..response_len]);
        }
    }
};
