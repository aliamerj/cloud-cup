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

                    const request_buffer = try allocator.alloc(u8, 4094);
                    defer allocator.free(request_buffer);

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
                        try stra.handle(client_fd, allocator, request, @constCast(&strategy_hash), path_info.path);
                        _ = std.posix.close(client_fd);
                        continue;
                    }

                    if (path_info.sub) {
                        var paths = std.mem.split(u8, path_info.path[1..], "/");
                        var matched = false;
                        while (paths.next()) |path| {
                            std.debug.print("paths is {s}\n", .{path});
                            const route = try std.fmt.allocPrint(allocator, "/{s}/*", .{path});
                            defer allocator.free(route);
                            var strategy = strategy_hash.get(route) orelse continue;
                            try strategy.handle(client_fd, allocator, request, @constCast(&strategy_hash), route);
                            _ = std.posix.close(client_fd);
                            matched = true;
                            break;
                        }
                        if (matched) continue;
                    }

                    var general_strategy = strategy_hash.get("*") orelse return error.MissingMainRoute;
                    try general_strategy.handle(client_fd, allocator, request, @constCast(&strategy_hash), "*");
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
