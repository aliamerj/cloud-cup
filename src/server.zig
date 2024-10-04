const std = @import("std");
const Config = @import("config/config.zig").Config;
const Strategy = @import("load_balancer/Strategy.zig").Strategy;
const Epoll = @import("http/epoll_handler.zig").Epoll;
const ops = @import("http/server_operations.zig");
const utils = @import("utils/utils.zig");

pub const Server = struct {
    config: Config,

    pub fn init(config: Config) Server {
        return Server{
            .config = config,
        };
    }

    pub fn run(self: Server) !void {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();

        var strategy_hash = std.StringHashMap(Strategy).init(allocator);
        defer {
            var it = strategy_hash.iterator();
            while (it.next()) |e| {
                e.value_ptr.round_robin.backends.deinit();
            }
            strategy_hash.deinit();
        }
        var it = self.config.routes.iterator();
        while (it.next()) |e| {
            const strategy = try e.value_ptr.routeSetup();

            const strategy_init = try strategy.init(e.value_ptr.backends, allocator);
            try strategy_hash.put(e.key_ptr.*, strategy_init);
        }

        var server_addy = try utils.parseServerAddress(self.config.root);

        var tcp_server = try server_addy.listen(.{
            .reuse_port = true,
            .reuse_address = true,
        });
        defer tcp_server.deinit();
        std.log.info("Server listening on {s}\n", .{self.config.root});
        try startServer(tcp_server, strategy_hash, allocator);
    }

    // strat the server with epoll
    fn startServer(tcp_server: std.net.Server, strategy_hash: std.StringHashMap(Strategy), allocator: std.mem.Allocator) !void {
        const epoll = try Epoll.init(tcp_server);
        defer epoll.deinit();

        var events: [1024]std.os.linux.epoll_event = undefined;

        while (true) {
            const nfds = epoll.wait(&events);
            for (events[0..nfds]) |event| {
                if (event.data.fd == tcp_server.stream.handle) {
                    try ops.acceptIncomingConnections(@constCast(&tcp_server), epoll);
                } else {
                    const client_fd = event.data.fd;
                    var strategy = strategy_hash.get("/").?;
                    try strategy.handle(client_fd, allocator);

                    // try handleClientRequest(&backends, &servers_down, &server_key, client_fd, allocator);
                    _ = std.posix.close(client_fd);
                }
            }
        }
    }

    // set up load balancer
    fn setupLoadBalancer(self: Server, strategy_hash: *std.StringHashMap(Strategy), allocator: std.mem.Allocator) !void {
        var it = self.config.routes.iterator();
        while (it.next()) |e| {
            const strategy = try e.value_ptr.routeSetup();
            const Strategy_init = try strategy.init(e.value_ptr.backends, allocator);

            try strategy_hash.put(e.key_ptr.*, Strategy_init);
        }
    }
};
