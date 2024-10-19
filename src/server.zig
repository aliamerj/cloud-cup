const std = @import("std");
const Config = @import("config/config.zig").Config;
const Config_Mangment = @import("config/config_managment.zig").Config_Manager;
const Strategy = @import("load_balancer/Strategy.zig").Strategy;
const Epoll = @import("http/epoll_handler.zig").Epoll;
const ops = @import("http/server_operations.zig");
const utils = @import("utils/utils.zig");
const cli = @import("cup_cli/cup_cli.zig");
const Pool = std.Thread.Pool;
const WaitGroup = std.Thread.WaitGroup;

pub const Server = struct {
    config: *Config,
    allocator: std.mem.Allocator,

    pub fn init(config: *Config, allocator: std.mem.Allocator) Server {
        return Server{
            .config = config,
            .allocator = allocator,
        };
    }

    pub fn run(self: Server) !void {
        _ = try self.config.applyConfig();

        var server_addy = try utils.parseServerAddress(self.config.root);

        var tcp_server = try server_addy.listen(.{
            .reuse_port = true,
            .reuse_address = true,
        });
        defer tcp_server.deinit();
        std.log.info("Server listening on {s}\n", .{self.config.root});

        try self.startServer(tcp_server);
    }

    // strat the server with epoll
    fn startServer(self: Server, tcp_server: std.net.Server) !void {
        const epoll = try Epoll.init(tcp_server);
        defer epoll.deinit();

        var config_manger = Config_Mangment.init(self.allocator);
        try config_manger.pushNewConfig(self.config.*);

        var thread_safe_arena: std.heap.ThreadSafeAllocator = .{
            .child_allocator = self.allocator,
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

        try thread_pool.spawn(cli.setupCliSocket, .{
            &config_manger,
            &arena,
        });

        while (true) {
            const nfds = epoll.wait(&events);
            for (events[0..nfds]) |event| {
                if (event.data.fd == tcp_server.stream.handle) {
                    try ops.acceptIncomingConnections(@constCast(&tcp_server), epoll);
                } else {
                    const client_fd = event.data.fd;

                    try thread_pool.spawn(handleRequest, .{
                        &wait_group,
                        &arena,
                        epoll.epoll_fd,
                        client_fd,
                        &config_manger,
                    });
                }
            }
        }
        // Work on threads after scheduling all tasks
        thread_pool.waitAndWork(&wait_group);
    }

    fn handleRequest(
        wait_group: *WaitGroup,
        allocator: *const std.mem.Allocator,
        epoll_fd: std.posix.fd_t,
        client_fd: std.posix.fd_t,
        config_manager: *Config_Mangment,
    ) void {
        wait_group.start();
        defer wait_group.finish();

        var config = config_manager.getCurrentConfig();

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

        var selected_strategy = config.strategy_hash.get(path_info.path);

        if (selected_strategy) |_| {
            selected_strategy.?.handle(client_fd, request, response, config, path_info.path) catch {};
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
                var strategy = config.strategy_hash.get(route) orelse continue;
                strategy.handle(client_fd, request, response, config, route) catch {};
                ops.closeConnection(epoll_fd, client_fd) catch {};
                return;
            }
        }
        var general_strategy = config.strategy_hash.get("*") orelse unreachable;

        general_strategy.handle(client_fd, request, response, config, "*") catch {};
        ops.closeConnection(epoll_fd, client_fd) catch {};
    }
};
