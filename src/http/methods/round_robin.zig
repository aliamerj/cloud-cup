const std = @import("std");

const h = @import("../http.zig");

pub const Hash_map = std.AutoHashMap(usize, u8);
pub const Array_list = std.ArrayList(h.Server);

pub const RoundRobin = struct {
    const max_attempts: u32 = 5;
    const wait_time = std.time.ns_per_s * 2; // Wait 2 seconds between attempts

    current_index: usize = 0,
    servers: Array_list = undefined,
    attempts_table: Hash_map = undefined,
    gpa: std.heap.GeneralPurposeAllocator(.{}) = undefined,

    pub fn init(self: *RoundRobin, servers: []h.Server) !void {
        self.gpa = std.heap.GeneralPurposeAllocator(.{}){};

        self.servers = Array_list.init(self.gpa.allocator());
        try self.servers.appendSlice(servers);
        self.attempts_table = Hash_map.init(self.gpa.allocator());
    }

    pub fn deinit(self: *RoundRobin) void {
        self.servers.deinit();
        self.attempts_table.deinit();
        _ = self.gpa.deinit();
    }

    pub fn handle(self: *RoundRobin, request: *const []u8, response_writer: *const std.net.Stream.Writer) !void {
        const len = self.servers.items.len;

        // Base case: if there are no servers left, return a 502 Bad Gateway response
        if (len == 0) {
            return self.sendBadGateway(response_writer);
        }

        // Ensure current_index is within bounds
        if (self.current_index >= len) {
            self.current_index = 0;
        }

        // Get the current server attempt count
        if (self.attempts_table.get(self.current_index)) |current_attempt| {
            if (current_attempt >= max_attempts) {
                // Remove the server if it has reached the maximum number of attempts
                _ = self.servers.orderedRemove(self.current_index);

                // Reset current_index to stay within the bounds after removal
                if (self.current_index >= self.servers.items.len) {
                    self.current_index = 0;
                }

                // Recur to try the next server
                return self.handle(request, response_writer);
            }
            if (current_attempt > 0) {
                // If the current attempt count is zero, wait before retrying
                std.time.sleep(wait_time);
            }
        }

        // Get the server to try
        const server = self.servers.items[self.current_index];
        self.current_index = (self.current_index + 1) % self.servers.items.len;

        // Attempt to connect and forward the request
        connectAndForwardRequest(server, request, response_writer) catch |err| {
            std.debug.print("Failed to connect to server at {s}:{d}. Error: {any}\n", .{ server.host, server.port, err });

            // Increment the attempt count for this server
            const value = try self.attempts_table.getOrPut(self.current_index);

            if (value.found_existing) {
                value.value_ptr.* += 1;
            } else {
                value.value_ptr.* = 1;
            }

            // Recur to try the next server
            return self.handle(request, response_writer);
        };

        // Reset the attempt count on success
        self.attempts_table.put(self.current_index, 0) catch unreachable;
    }

    fn sendBadGateway(self: *RoundRobin, response_writer: *const std.net.Stream.Writer) !void {
        _ = self;
        const response = "HTTP/1.1 502 Bad Gateway\r\nContent-Type: text/plain\r\nContent-Length: 16\r\n\r\n502 Bad Gateway\n";
        try response_writer.writeAll(response);
    }

    fn connectAndForwardRequest(server: h.Server, request: *const []u8, response_writer: *const std.net.Stream.Writer) !void {
        const address = try std.net.Address.parseIp4(server.host, server.port);
        const socket = try std.net.tcpConnectToAddress(address);
        defer socket.close();

        std.debug.print("Sending request to {s}:{d}:\n{s}\n", .{ server.host, server.port, request.* });

        try socket.writer().writeAll(request.*);

        var response_buffer: [4096]u8 = undefined;
        var response_len: usize = 0;

        while (true) {
            // Try reading a chunk of the response
            response_len = try socket.reader().read(&response_buffer);

            // If response_len is 0, the server has closed the connection, break the loop
            if (response_len == 0) break;

            std.debug.print("Received response chunk from {s}:{d}:\n{s}\n", .{ server.host, server.port, response_buffer[0..response_len] });

            // Send this chunk to the client
            try response_writer.writeAll(response_buffer[0..response_len]);
        }
    }
};
