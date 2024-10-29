const std = @import("std");
const utils = @import("utils/utils.zig");
const cli = @import("cup_cli/cup_cli.zig");

const Config = @import("config/config.zig").Config;
const Config_Mangment = @import("config/config_managment.zig").Config_Manager;

const startWorker = @import("core/worker/worker.zig").startWorker;

pub const Server = struct {
    pub fn run(config: Config) !void {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();

        var server_addy = utils.parseServerAddress(config.conf.root) catch |err| {
            std.log.err("{any}\n", .{err});
            return;
        };
        var tcp_server = server_addy.listen(.{
            .reuse_address = true,
            .reuse_port = true,
        }) catch |err| {
            std.log.err("{any}\n", .{err});
            return;
        };

        defer tcp_server.deinit();
        std.log.info("Server listening on {s}\n", .{config.conf.root});

        var config_manger = Config_Mangment.init(config.allocator);
        try config_manger.pushNewConfig(config);
        defer config_manger.deinit();

        const cpu_count = try std.Thread.getCpuCount();
        const workers = try allocator.alloc(i32, cpu_count);
        defer allocator.free(workers);

        // Spawn initial workers
        for (0..cpu_count) |i| {
            try spawnWorker(workers, i, tcp_server, config_manger);
        }

        for (workers) |pid| {
            _ = std.posix.waitpid(pid, 0); // Wait for each worker to exit
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
            },
        }
    }
};
