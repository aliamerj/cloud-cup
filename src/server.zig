const std = @import("std");
const Config = @import("config/config.zig").Config;
const Strategy = @import("load_balancer/Strategy.zig").Strategy;
const Epoll = @import("http/epoll_handler.zig").Epoll;
const ops = @import("http/server_operations.zig");
const utils = @import("utils/utils.zig");

pub const Server = struct {
    config: Config,
    allocator: std.mem.Allocator,

    pub fn init(config: Config, allocator: std.mem.Allocator) Server {
        return Server{
            .config = config,
            .allocator = allocator,
        };
    }

    pub fn run(self: Server) !void {
        var strategy_hash = std.StringHashMap(Strategy).init(self.allocator);
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
            const strategy_init = try strategy.init(e.value_ptr.backends, self.allocator);
            try strategy_hash.put(e.key_ptr.*, strategy_init);
        }

        var server_addy = try utils.parseServerAddress(self.config.root);

        var tcp_server = try server_addy.listen(.{
            .reuse_port = true,
            .reuse_address = true,
        });
        defer tcp_server.deinit();
        std.log.info("Server listening on {s}\n", .{self.config.root});
        try startServer(tcp_server, strategy_hash, self.allocator);
    }

    // strat the server with epoll
    fn startServer(tcp_server: std.net.Server, strategy_hash: std.StringHashMap(Strategy), allocator: std.mem.Allocator) !void {
        const epoll = try Epoll.init(tcp_server);
        defer epoll.deinit();

        var events: [1024]std.os.linux.epoll_event = undefined;
        const request_buffer = try allocator.alloc(u8, 4094);
        const response = try allocator.alloc(u8, 4094);
        defer allocator.free(request_buffer);
        defer allocator.free(response);

        while (true) {
            const nfds = epoll.wait(&events);
            for (events[0..nfds]) |event| {
                if (event.data.fd == tcp_server.stream.handle) {
                    try ops.acceptIncomingConnections(@constCast(&tcp_server), epoll);
                } else {
                    const client_fd = event.data.fd;

                    const request = ops.readClientRequest(client_fd, request_buffer) catch {
                        try ops.sendBadGateway(client_fd);
                        return;
                    };

                    const path_info = utils.extractPath(request) catch {
                        try ops.sendBadGateway(client_fd);
                        return;
                    };

                    const selected_strategy = strategy_hash.get(path_info.path);
                    if (selected_strategy) |strategy| {
                        var stra = @constCast(&strategy);
                        try stra.handle(client_fd, request, response, @constCast(&strategy_hash), path_info.path);
                        try ops.closeConnection(epoll.epoll_fd, client_fd);
                        continue;
                    }

                    if (path_info.sub) {
                        var paths = std.mem.split(u8, path_info.path[1..], "/");
                        var matched = false;
                        while (paths.next()) |path| {
                            const route = try std.fmt.allocPrint(allocator, "/{s}/*", .{path});
                            defer allocator.free(route);
                            var strategy = strategy_hash.get(route) orelse continue;
                            try strategy.handle(client_fd, request, response, @constCast(&strategy_hash), route);
                            try ops.closeConnection(epoll.epoll_fd, client_fd);
                            matched = true;
                            break;
                        }
                        if (matched) continue;
                    }

                    var general_strategy = strategy_hash.get("*") orelse return error.MissingMainRoute;
                    try general_strategy.handle(client_fd, request, response, @constCast(&strategy_hash), "*");
                    try ops.closeConnection(epoll.epoll_fd, client_fd);
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
