const std = @import("std");
const ops = @import("../server_ops/server_ops.zig");
const utils = @import("../../utils/utils.zig");
const cli = @import("../../cup_cli/cup_cli.zig");
const c = @import("../../core/connection/connection.zig");
const ssl = @import("../../ssl/SSL.zig");

const Config = @import("../../config/config.zig").Config;
const Strategy = @import("../../load_balancer/Strategy.zig").Strategy;
const Epoll = @import("../epoll/epoll_handler.zig").Epoll;
const Config_Manager = @import("../../config/config_managment.zig").Config_Manager;
const Shared_Config = @import("../shared_memory/SharedMemory.zig").SharedMemory([4096]u8);

const Pool = std.Thread.Pool;
const WaitGroup = std.Thread.WaitGroup;

const Connection = c.Connection;
const ConnectionData = c.ConnectionData;

// strat the server with epoll
pub fn startWorker(server_addy: std.net.Address, shared_config: Shared_Config) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config_manager = Config_Manager.init(allocator);
    defer config_manager.deinit();

    var tcp_server = server_addy.listen(.{
        .reuse_address = true,
        .reuse_port = true,
    }) catch |err| {
        std.log.err("Failed to start listening on server: {any}\n", .{err});
        return;
    };
    defer tcp_server.deinit();

    const epoll = try Epoll.init(tcp_server);
    defer epoll.deinit();

    var connection = Connection.init(allocator);
    defer connection.deinit();

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

    // Spawn configuration watcher
    thread_pool.spawnWg(&wait_group, configChangeWatcher, .{ allocator, &config_manager, shared_config });

    try mainEventLoop(tcp_server, epoll, &wait_group, &thread_pool, &config_manager, connection);

    // Work on threads after scheduling all tasks
    thread_pool.waitAndWork(&wait_group);
}

fn mainEventLoop(
    tcp_server: std.net.Server,
    epoll: Epoll,
    wait_group: *WaitGroup,
    thread_pool: *Pool,
    config_manager: *Config_Manager,
    connection: Connection,
) !void {
    var events: [1024]std.os.linux.epoll_event = undefined;

    while (true) {
        const nfds = epoll.wait(&events);
        var config = config_manager.getCurrentConfig();
        for (events[0..nfds]) |event| {
            if (event.data.fd == tcp_server.stream.handle) {
                try ops.acceptIncomingConnections(tcp_server, epoll, &config.conf.ssl, connection);
            } else {
                const conn: ?*ConnectionData = @ptrFromInt(event.data.ptr);
                thread_pool.spawnWg(wait_group, handleRequest, .{
                    epoll.epoll_fd,
                    &config,
                    conn.?.*,
                    connection,
                });
            }
        }
    }
}

fn configChangeWatcher(allocator: std.mem.Allocator, config_manager: *Config_Manager, sh_config: Shared_Config) void {
    var current_config: usize = 0;
    var config: Config = undefined;
    defer config.deinit();

    while (true) {
        const file_data = sh_config.readData();

        var parts = std.mem.split(u8, file_data[0..], "|");
        const new_config = parseConfigVersion(parts.next().?) catch {
            return;
        };

        if (current_config != new_config) {
            const parsed_config = parseConfigJSON(parts.next().?);
            config = Config.init(parsed_config, allocator, null) catch |err| {
                std.log.err("Config parse error: {any}", .{err});
                return;
            };

            config_manager.pushNewConfig(config) catch |e| {
                std.log.err("push err:{any}", .{e});
                return;
            };
            current_config = new_config;
        }
        std.time.sleep(1_000_000_000);
    }
}

fn parseConfigVersion(data: []const u8) !usize {
    return std.fmt.parseInt(usize, data, 10) catch |err| {
        std.log.err("parse err: {any}", .{err});
        return err;
    };
}

fn parseConfigJSON(json_data: []const u8) []u8 {
    const json = std.mem.trimRight(u8, json_data, &[_]u8{ 0, '\n', '\r', ' ', '\t' });
    var buffer: [4096]u8 = undefined;

    std.mem.copyForwards(u8, &buffer, json);

    return buffer[0..json.len];
}

fn handleRequest(
    epoll_fd: std.posix.fd_t,
    config: *Config,
    conn: ConnectionData,
    connection: Connection,
) void {
    var request_buffer: [4094]u8 = undefined;
    var response_buffer: [4094]u8 = undefined;

    const request = ops.readClientRequest(conn, &request_buffer) catch {
        handleError(conn, epoll_fd, connection);
        return;
    };

    const path_info = utils.extractPath(request) catch {
        handleError(conn, epoll_fd, connection);
        return;
    };

    var selected_strategy = config.conf.strategy_hash.get(path_info.path);

    if (selected_strategy) |_| {
        selected_strategy.?.handle(conn, request, &response_buffer, config.*, path_info.path) catch {};
        ops.closeConnection(epoll_fd, conn, connection) catch {};
        return;
    }

    if (path_info.sub) {
        var paths = std.mem.split(u8, path_info.path[1..], "/");
        var buf_route: [1024]u8 = undefined;
        while (paths.next()) |path| {
            const route = std.fmt.bufPrint(&buf_route, "/{s}/*", .{path}) catch {
                return;
            };
            var strategy = config.conf.strategy_hash.get(route) orelse continue;
            strategy.handle(conn, request, &response_buffer, config.*, route) catch {};
            ops.closeConnection(epoll_fd, conn, connection) catch {};
            return;
        }
    }
    var general_strategy = config.conf.strategy_hash.get("*") orelse unreachable;

    general_strategy.handle(conn, request, &response_buffer, config.*, "*") catch {};
    ops.closeConnection(epoll_fd, conn, connection) catch {};
}

fn handleError(conn: ConnectionData, epoll_fd: std.posix.fd_t, connection: Connection) void {
    ops.sendBadGateway(conn) catch {};
    ops.closeConnection(epoll_fd, conn, connection) catch {};
}
