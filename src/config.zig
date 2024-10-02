const std = @import("std");
const Http = @import("http/http.zig").Http;
const Strategy = @import("http/Strategy.zig").Strategy;
const Epoll = @import("utils/epoll.zig").Epoll;
const Allocator = std.mem.Allocator;

const Options = struct {
    host: []const u8,
    port: u16,
    http: Http,
};

const epoll_event_handler = struct {
    fd: std.os.fd_t,
    handle: fn (handler: *epoll_event_handler, events: u32) void,
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
        var strategy = getHttpStrategy(self.options.http.httpSetup()) catch |err| {
            std.log.err("Unsupported load balancing Strategy: '{s}'. The method '{s}' is not supported by the current load balancer configuration.", .{
                self.options.http.method.?,
                self.options.http.method.?,
            });
            return err;
        };

        const server_addy = try std.net.Address.parseIp4(self.options.host, self.options.port);
        var tcp_server = try server_addy.listen(.{
            .reuse_port = true,
            .reuse_address = true,
        });
        defer tcp_server.deinit();

        const epoll = try Epoll.init(tcp_server);
        defer epoll.deinit();

        std.log.info("Server listening on {s}:{any}\n", .{ self.options.host, self.options.port });
        try strategy.handle(&tcp_server, epoll, self.options.http.servers);
    }

    fn getHttpStrategy(strategy: ?Strategy) !Strategy {
        if (strategy) |stra| {
            return stra;
        }
        std.log.err("Unsupported load balancing Strategy", .{});
        return error.Unsupported;
    }
};
