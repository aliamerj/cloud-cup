const std = @import("std");
const h = @import("http/http.zig");
const algo = @import("http/Algorithm.zig");
const Allocator = std.mem.Allocator;

const Options = struct {
    host: []const u8,
    port: u16,
    http: ?h.Http = null,
};

pub const Config = struct {
    options: Options,

    pub fn init(json_file_path: []const u8, allocator: Allocator) !Config {
        const data = try std.fs.cwd().readFileAlloc(allocator, json_file_path, 512);
        defer allocator.free(data);
        const parse = try std.json.parseFromSlice(Options, allocator, data, .{ .allocate = .alloc_always });
        defer parse.deinit();

        return Config{
            .options = parse.value,
        };
    }

    pub fn run(self: *const Config) !void {
        std.debug.print("Starting server on {s}:{any}\n", .{ self.options.host, self.options.port });
        const address = try std.net.Address.parseIp4(self.options.host, self.options.port);
        var server = try address.listen(.{});
        std.debug.print("Server listening on {s}:{any}\n", .{ self.options.host, self.options.port });

        var method: ?algo.Algorithm = null;

        if (self.options.http) |http| {
            method = http.httpSetup();
            try method.?.init(http.servers);
        }
        defer method.?.deinit();

        while (true) {
            const client = try server.accept();
            defer client.stream.close();

            const client_writer = client.stream.writer();
            const client_reader = client.stream.reader();

            if (method == null) {
                // Send the response to the client
                try client_writer.writeAll("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 13\r\n\r\n No HTTP configuration provided.\n");
                return;
            }

            // Read the HTTP request
            var request_buffer: [8192]u8 = undefined;
            const request_len = try client_reader.read(&request_buffer);
            try method.?.handle(&request_buffer[0..request_len], &client_writer);
        }
    }
};
