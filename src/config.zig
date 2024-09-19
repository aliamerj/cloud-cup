const std = @import("std");
const Http = @import("http/http.zig").Http;
const Algorithm = @import("http/Algorithm.zig").Algorithm;
const EpollNonblock = @import("http/utils/epoll_nonblock.zig").EpollNonblock;
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
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();

        const strategy = getHttpStrategy(self.options.http.httpSetup()) catch |err| {
            std.log.err("Unsupported load balancing method: '{s}'. The method '{s}' is not supported by the current load balancer configuration.", .{
                self.options.http.method.?,
                self.options.http.method.?,
            });
            return err;
        };
        defer strategy.deinit();

        // start the server
        const address = try std.net.Address.parseIp4(self.options.host, self.options.port);
        var tcp_server = try address.listen(.{
            .reuse_address = true,
            .reuse_port = true,
        });
        defer tcp_server.deinit();

        std.log.info("Server listening on {s}:{any}\n", .{ self.options.host, self.options.port });

        var epoll = try EpollNonblock.init(tcp_server, allocator);
        defer epoll.deinit();

        try epoll.register();
        // Handle the connections and incoming data
        try strategy.handle(&tcp_server, &epoll);
    }

    fn getHttpStrategy(strategy: ?Algorithm) !Algorithm {
        if (strategy) |stra| {
            return stra;
        }
        std.log.err("Unsupported load balancing Strategy", .{});
        return error.ConnectFail;
    }
};
