const std = @import("std");
const ops = @import("../../http/server_operations.zig");
const utils = @import("../../utils/utils.zig");
const cli = @import("../../cup_cli/cup_cli.zig");
const c = @import("../../http/connection.zig");
const ssl = @import("../../ssl/SSL.zig");

const Config = @import("../../config/config.zig").Config;
const Config_Mangment = @import("../../config/config_managment.zig").Config_Manager;
const Strategy = @import("../../load_balancer/Strategy.zig").Strategy;
const Epoll = @import("../../http/epoll_handler.zig").Epoll;

const Pool = std.Thread.Pool;
const WaitGroup = std.Thread.WaitGroup;

const Connection = c.Connection;
const ConnectionData = c.ConnectionData;

// strat the server with epoll
pub fn startWorker(tcp_server: std.net.Server, config_manger: Config_Mangment) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    defer @constCast(&config_manger).deinit();

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

    var connection = Connection.init(allocator);
    defer connection.deinit();

    var events: [1024]std.os.linux.epoll_event = undefined;

    while (true) {
        const nfds = epoll.wait(&events);
        const config = @constCast(&config_manger).getCurrentConfig();

        for (events[0..nfds]) |event| {
            if (event.data.fd == tcp_server.stream.handle) {
                try ops.acceptIncomingConnections(tcp_server, epoll, config.conf.ssl, connection);
            } else {
                const conn: ?*ConnectionData = @ptrFromInt(event.data.ptr);
                try thread_pool.spawn(handleRequest, .{
                    &wait_group,
                    &arena,
                    epoll.epoll_fd,
                    config,
                    conn.?.*,
                    connection,
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
    config: Config,
    conn: ConnectionData,
    connection: Connection,
) void {
    wait_group.start();
    defer wait_group.finish();

    var request_buffer: [4094]u8 = undefined;
    var response_buffer: [4094]u8 = undefined;

    const request = ops.readClientRequest(conn, &request_buffer) catch {
        ops.sendBadGateway(conn) catch {};
        ops.closeConnection(epoll_fd, conn, connection) catch {};
        return;
    };

    const path_info = utils.extractPath(request) catch {
        ops.sendBadGateway(conn) catch {};
        ops.closeConnection(epoll_fd, conn, connection) catch {};
        return;
    };

    var selected_strategy = config.conf.strategy_hash.get(path_info.path);

    if (selected_strategy) |_| {
        selected_strategy.?.handle(conn, request, &response_buffer, config, path_info.path) catch {};
        ops.closeConnection(epoll_fd, conn, connection) catch {};
        return;
    }

    if (path_info.sub) {
        var paths = std.mem.split(u8, path_info.path[1..], "/");
        while (paths.next()) |path| {
            const route = std.fmt.allocPrint(allocator.*, "/{s}/*", .{path}) catch {
                return;
            };
            defer allocator.free(route);
            var strategy = config.conf.strategy_hash.get(route) orelse continue;
            strategy.handle(conn, request, &response_buffer, config, route) catch {};
            ops.closeConnection(epoll_fd, conn, connection) catch {};
            return;
        }
    }
    var general_strategy = config.conf.strategy_hash.get("*") orelse unreachable;

    general_strategy.handle(conn, request, &response_buffer, config, "*") catch {};
    ops.closeConnection(epoll_fd, conn, connection) catch {};
}
