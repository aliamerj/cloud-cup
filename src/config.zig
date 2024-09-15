const std = @import("std");
const Http = @import("http/http.zig").Http;
const algo = @import("http/Algorithm.zig");
const Allocator = std.mem.Allocator;

const Options = struct {
    host: []const u8,
    port: u16,
    http: Http,
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
        const address = try std.net.Address.parseIp4(self.options.host, self.options.port);
        var server = try address.listen(.{});
        std.log.info("Server listening on {s}:{any}\n", .{ self.options.host, self.options.port });

        if (self.options.http.httpSetup()) |method| {
            try method.init(self.options.http.servers);
            defer method.deinit();
            try method.handle(&server);
        }

        std.log.err("Unsupported load balancing method: '{s}'. The method '{s}' is not supported by the current load balancer configuration.", .{ self.options.http.method.?, self.options.http.method.? });
    }
};
