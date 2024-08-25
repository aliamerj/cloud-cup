const std = @import("std");

const Allocator = std.mem.Allocator;

const Options = struct {
    host: []const u8,
    port: u16,
};

pub const Config = struct {
    options: Options,
    allocator: Allocator,

    pub fn init(allocator: Allocator, json_file_path: []const u8) !Config {
        const data = try std.fs.cwd().readFileAlloc(allocator, json_file_path, 512);
        defer allocator.free(data);
        const parse = try std.json.parseFromSlice(Options, allocator, data, .{ .allocate = .alloc_always });
        defer parse.deinit();

        return Config{
            .allocator = allocator,
            .options = parse.value,
        };
    }

    pub fn run(self: *const Config) !void {
        std.debug.print("Starting server on {s}:{any}\n", .{ self.options.host, self.options.port });
        const address = try std.net.Address.parseIp4(self.options.host, self.options.port);
        var server = try address.listen(.{});
        std.debug.print("Server listening on {s}:{any}\n", .{ self.options.host, self.options.port });

        while (true) {
            var client = try server.accept();
            defer client.stream.close();
            std.debug.print("Accepted connection from client\n", .{});

            const client_reader = client.stream.reader();
            const client_writer = client.stream.writer();

            // Read the HTTP request
            var request_buffer: [1024]u8 = undefined;
            const request_len = try client_reader.read(&request_buffer);

            // Print the request (optional)
            std.debug.print("Received request: {s}\n", .{request_buffer[0..request_len]});

            // Create a basic HTTP response
            const response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 13\r\n\r\nHello, World!";

            // Send the response to the client
            try client_writer.writeAll(response);
            std.debug.print("Sent response to client\n", .{});
        }
    }
};
