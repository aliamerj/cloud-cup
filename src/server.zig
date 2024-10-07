const std = @import("std");
const Config = @import("config/config.zig").Config;
const Strategy = @import("load_balancer/Strategy.zig").Strategy;
const Epoll = @import("http/epoll_handler.zig").Epoll;
const ops = @import("http/server_operations.zig");
const utils = @import("utils/utils.zig");

const Pool = std.Thread.Pool;
const WaitGroup = std.Thread.WaitGroup;

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

        var thread_safe_arena: std.heap.ThreadSafeAllocator = .{
            .child_allocator = allocator,
        };
        const arena = thread_safe_arena.allocator();

        var thread_pool: Pool = undefined;
        try thread_pool.init(Pool.Options{
            .allocator = arena,
        });
        defer thread_pool.deinit();

        var wait_group: WaitGroup = undefined;
        wait_group.reset();

        var events: [1024]std.os.linux.epoll_event = undefined;

        while (true) {
            const nfds = epoll.wait(&events);
            for (events[0..nfds]) |event| {
                if (event.data.fd == tcp_server.stream.handle) {
                    try ops.acceptIncomingConnections(@constCast(&tcp_server), epoll);
                } else {
                    const client_fd = event.data.fd;

                    try thread_pool.spawn(isPrimeRoutine, .{
                        &wait_group,
                        &arena,
                        epoll.epoll_fd,
                        client_fd,
                        strategy_hash,
                    });
                }
            }
        }
        // Work on threads after scheduling all tasks
        thread_pool.waitAndWork(&wait_group);
    }

    pub fn isPrimeRoutine(
        wait_group: *WaitGroup,
        allocator: *const std.mem.Allocator,
        epoll_fd: std.posix.fd_t,
        client_fd: std.posix.fd_t,
        strategy_hash: std.StringHashMap(Strategy),
    ) void {
        wait_group.start();
        defer wait_group.finish();

        const request_buffer = allocator.alloc(u8, 4094) catch unreachable;
        const response = allocator.alloc(u8, 4094) catch unreachable;
        defer allocator.free(request_buffer);
        defer allocator.free(response);

        const request = ops.readClientRequest(client_fd, request_buffer) catch {
            ops.sendBadGateway(client_fd) catch {};
            return;
        };

        const path_info = utils.extractPath(request) catch {
            ops.sendBadGateway(client_fd) catch {};
            return;
        };

        const selected_strategy = strategy_hash.get(path_info.path);
        if (selected_strategy) |strategy| {
            var stra = @constCast(&strategy);
            stra.handle(client_fd, request, response, @constCast(&strategy_hash), path_info.path) catch {};
            ops.closeConnection(epoll_fd, client_fd) catch {};
            return;
        }

        if (path_info.sub) {
            var paths = std.mem.split(u8, path_info.path[1..], "/");
            while (paths.next()) |path| {
                const route = std.fmt.allocPrint(allocator.*, "/{s}/*", .{path}) catch {
                    return;
                };
                defer allocator.free(route);
                var strategy = strategy_hash.get(route) orelse continue;
                strategy.handle(client_fd, request, response, @constCast(&strategy_hash), route) catch {};
                ops.closeConnection(epoll_fd, client_fd) catch {};
                return;
            }
        }

        var general_strategy = strategy_hash.get("*") orelse return;
        general_strategy.handle(client_fd, request, response, @constCast(&strategy_hash), "*") catch {};
        ops.closeConnection(epoll_fd, client_fd) catch {};
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
