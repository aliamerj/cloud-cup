const std = @import("std");
const utils = @import("utils/utils.zig");
const cli = @import("cup_cli/cup_cli.zig");

const Config = @import("config/config.zig").Config;
const Config_Mangment = @import("config/config_managment.zig").Config_Manager;

const Pool = std.Thread.Pool;
const WaitGroup = std.Thread.WaitGroup;

const startWorker = @import("core/worker/worker.zig").startWorker;

pub const Server = struct {
    pub fn run(config: Config) !void {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();

        var server_addy = utils.parseServerAddress(config.conf.root) catch |err| {
            std.log.err("Failed to parse server address: {any}\n", .{err});
            return;
        };

        var tcp_server = server_addy.listen(.{
            .reuse_address = true,
            .reuse_port = true,
        }) catch |err| {
            std.log.err("Failed to start listening on server: {any}\n", .{err});
            return;
        };

        defer tcp_server.deinit();
        std.log.info("Server listening on {s}\n", .{config.conf.root});

        var config_manger = Config_Mangment.init(config.allocator);
        try config_manger.pushNewConfig(config);
        defer config_manger.deinit();

        const cpu_count = try std.Thread.getCpuCount();
        const workers = try allocator.alloc(i32, cpu_count);
        defer {
            for (workers, 0..) |pid, i| {
                _ = i;
                std.posix.kill(pid, std.posix.SIG.TERM) catch |err| {
                    std.log.err("Failed exit pid {any} with error {any}\n", .{ pid, err });
                };
            }
            allocator.free(workers);
        }

        // Spawn initial workers
        for (0..cpu_count) |i| {
            try spawnWorker(workers, i, tcp_server, config_manger);
        }

        var thread_pool: Pool = undefined;
        var thread_safe_arena: std.heap.ThreadSafeAllocator = .{ .child_allocator = allocator };
        const arena = thread_safe_arena.allocator();
        try thread_pool.init(.{ .allocator = arena });
        defer thread_pool.deinit();

        var wait_group: WaitGroup = undefined;
        wait_group.reset();

        for (workers, 0..) |_, index| {
            thread_pool.spawnWg(&wait_group, monitoringWorker, .{ workers, index, tcp_server, config_manger });
        }

        thread_pool.waitAndWork(&wait_group);
    }

    pub fn monitoringWorker(workers: []i32, index: usize, tcp_server: std.net.Server, config_manger: Config_Mangment) void {
        var pid: i32 = workers[index];
        while (true) {
            const res = std.posix.waitpid(pid, 0);

            switch (res.status) {
                0 => std.debug.print("Worker {d} exited normally.\n", .{res.pid}),
                9 => std.debug.print("Worker {d} killed by SIGKILL (likely kill -9), respawning.\n", .{res.pid}),
                15 => std.debug.print("Worker {d} terminated by SIGTERM (likely regular kill), respawning.\n", .{res.pid}),
                else => std.debug.print("Worker {d} terminated with unknown status {d}, respawning.\n", .{ res.pid, res.status }),
            }

            // Respawn worker regardless of termination reason
            spawnWorker(workers, index, tcp_server, config_manger) catch |err| {
                std.log.err("Error spawning worker: {any}\n", .{err});
            };
            pid = workers[index];
        }
    }

    fn spawnWorker(workers: []i32, index: usize, tcp_server: std.net.Server, config_manger: Config_Mangment) !void {
        const pid = try std.posix.fork();
        switch (pid) {
            0 => {
                try startWorker(tcp_server, config_manger);
                std.posix.exit(0);
            },
            -1 => return error.ForkFailed,
            else => {
                workers[index] = pid;
                std.debug.print("Spawned new worker with PID {d} at index {d}\n", .{ pid, index });
            },
        }
    }
};
