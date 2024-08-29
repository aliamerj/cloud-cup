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

    pub fn handle(self: *RoundRobin, request: *const []u8, response_writer: *const std.net.Stream.Writer) !void {
        const len = self.servers.count();

        // Base case: if there are no servers left, return a 502 Bad Gateway response
        if (len == 0) {
            return self.sendBadGateway(response_writer);
        }

        // Ensure current_index is within bounds
        var server_iter = self.servers.iterator();
        while (server_iter.next()) |entry| {
            var server_data = entry.value_ptr.*;
            const server_key = entry.key_ptr.*;
            if (server_data.attempts >= max_attempts) {
                _ = self.servers.remove(server_key);
                continue;
            }

            connectAndForwardRequest(server_data.server, request, response_writer) catch {
                server_data.attempts += 1;
                try self.servers.put(server_key, server_data);
            };

            if (server_data.attempts > 0) {
                server_data.attempts = 0;
                try self.servers.put(server_key, server_data);
            }
            return;
        }

        return self.sendBadGateway(response_writer);
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
        var response_buffer: [4096]u8 = undefined;
        while (true) {
            const response_len = try socket.reader().read(&response_buffer);
            if (response_len == 0) break;
            try response_writer.writeAll(response_buffer[0..response_len]);
        }
    }
};
