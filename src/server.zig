const std = @import("std");
const utils = @import("utils/utils.zig");
const cli = @import("cup_cli/cup_cli.zig");

const Config = @import("config/config.zig").Config;
const Config_Manager = @import("config/config_managment.zig").Config_Manager;

const SharedConfig = @import("core/shared_memory/SharedMemory.zig").SharedMemory([4096]u8);

const Pool = std.Thread.Pool;
const WaitGroup = std.Thread.WaitGroup;

const startWorker = @import("core/worker/worker.zig").startWorker;

pub const Server = struct {
    pub fn run(config_manager: *Config_Manager, shared_config: SharedConfig) !void {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        const allocator = gpa.allocator();
        defer _ = gpa.deinit();

        const config = config_manager.getCurrentConfig();

        const server_address = parseServerAddress(config.conf.root) catch |err| {
            std.log.err("Failed to parse server address: {any}\n", .{err});
            return;
        };

        std.log.info("Server listening on {s}\n", .{config.conf.root});

        const cpu_count = try std.Thread.getCpuCount();
        const workers = try initializeWorkerArray(cpu_count, allocator);
        defer terminateWorkers(workers);

        spawnInitialWorkers(workers, server_address, shared_config, config_manager.*) catch |err| {
            std.log.err("Error spawning initial workers: {any}\n", .{err});
            return;
        };

        const cli_pid = try spawnCli(shared_config);
        defer terminateProcess(cli_pid);

        try monitorProcesses(workers, cli_pid, server_address, shared_config, allocator, config_manager.*);
    }

    fn parseServerAddress(root: []const u8) !std.net.Address {
        return utils.parseServerAddress(root);
    }

    fn initializeWorkerArray(count: usize, allocator: std.mem.Allocator) ![]i32 {
        return allocator.alloc(i32, count);
    }

    fn terminateWorkers(workers: []i32) void {
        for (workers) |pid| {
            terminateProcess(pid);
        }
    }

    fn terminateProcess(pid: i32) void {
        std.posix.kill(pid, std.posix.SIG.TERM) catch |err| {
            std.log.err("Failed to terminate process {any} with error {any}\n", .{ pid, err });
        };
    }

    fn spawnInitialWorkers(
        workers: []i32,
        address: std.net.Address,
        shared_config: SharedConfig,
        config_manager: Config_Manager,
    ) !void {
        for (0..workers.len) |i| {
            try spawnWorker(workers, i, address, shared_config, config_manager);
        }
    }

    fn spawnWorker(
        workers: []i32,
        index: usize,
        address: std.net.Address,
        shared_config: SharedConfig,
        config_manager: Config_Manager,
    ) !void {
        const pid = try std.posix.fork();
        switch (pid) {
            0 => {
                try startWorker(address, config_manager, shared_config);
                std.posix.exit(0);
            },
            -1 => return error.ForkFailed,
            else => {
                workers[index] = pid;
            },
        }
    }

    fn spawnCli(shared_config: SharedConfig) !i32 {
        const pid = try std.posix.fork();
        switch (pid) {
            0 => {
                cli.setupCliSocket(shared_config);
                std.posix.exit(0);
            },
            -1 => return error.ForkFailed,
            else => return pid,
        }
    }

    fn monitorProcesses(
        workers: []i32,
        cli_pid: i32,
        address: std.net.Address,
        shared_config: SharedConfig,
        allocator: std.mem.Allocator,
        config_manager: Config_Manager,
    ) !void {
        var thread_pool: Pool = undefined;
        var thread_safe_arena: std.heap.ThreadSafeAllocator = .{ .child_allocator = allocator };
        const arena = thread_safe_arena.allocator();

        try thread_pool.init(.{ .allocator = arena });
        defer thread_pool.deinit();

        var wait_group: WaitGroup = undefined;
        wait_group.reset();

        thread_pool.spawnWg(&wait_group, monitorCli, .{ cli_pid, shared_config });

        for (workers, 0..) |_, index| {
            thread_pool.spawnWg(&wait_group, monitorWorker, .{
                workers,
                index,
                address,
                shared_config,
                config_manager,
            });
        }

        thread_pool.waitAndWork(&wait_group);
    }

    fn monitorWorker(
        workers: []i32,
        index: usize,
        server_addy: std.net.Address,
        shared_config: SharedConfig,
        config_manager: Config_Manager,
    ) void {
        var pid: i32 = workers[index];
        while (true) {
            const res = std.posix.waitpid(pid, 0);
            logTermination("Worker", res.pid, res.status);

            // Respawn worker regardless of termination reason
            spawnWorker(workers, index, server_addy, shared_config, config_manager) catch |err| {
                std.log.err("Error spawning worker: {any}\n", .{err});
            };
            pid = workers[index];
        }
    }

    fn monitorCli(cli_pid: i32, shared_config: SharedConfig) void {
        var pid = cli_pid;
        while (true) {
            const res = std.posix.waitpid(pid, 0);
            logTermination("CLI", res.pid, res.status);

            pid = spawnCli(shared_config) catch |err| {
                std.log.err("Error respawning CLI: {any}\n", .{err});
                return;
            };
        }
    }

    fn logTermination(process: []const u8, pid: i32, status: u32) void {
        switch (status) {
            0 => std.debug.print("{s} {d} exited normally.\n", .{ process, pid }),
            9 => std.debug.print("{s} {d} killed by SIGKILL, respawning.\n", .{ process, pid }),
            15 => std.debug.print("{s} {d} terminated by SIGTERM, respawning.\n", .{ process, pid }),
            else => std.debug.print("{s} {d} terminated with unknown status {d}, respawning.\n", .{ process, pid, status }),
        }
    }
};
