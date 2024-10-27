const std = @import("std");
const ssl_struct = @import("../ssl/SSL.zig");
const Strategy = @import("../load_balancer/Strategy.zig").Strategy;
const Epoll = @import("../http/epoll_handler.zig").Epoll;
const Route = @import("../load_balancer/route.zig").Route;
const Builder = @import("../config/config_builder.zig").Builder;
const Error = @import("../utils/error_channel.zig").Error;

const Allocator = std.mem.Allocator;

const Conf = struct {
    root: []const u8,
    routes: std.StringHashMap(Route),
    strategy_hash: std.StringHashMap(Strategy) = undefined,
    ssl: ?*ssl_struct.SSL_CTX,
};

pub const Config = struct {
    config_parsed: std.json.Parsed(std.json.Value),
    allocator: Allocator,
    conf: Conf = undefined,
    //
    pub fn readConfigFile(config_path: []const u8, allocator: Allocator) !std.json.Parsed(std.json.Value) {
        // Read the JSON file contents
        const data = try std.fs.cwd().readFileAlloc(allocator, config_path, 8024);
        defer allocator.free(data);

        // Parse the JSON data
        return try std.json.parseFromSlice(std.json.Value, allocator, data, .{ .allocate = .alloc_always });
    }

    pub fn init(parsed: std.json.Parsed(std.json.Value), allocator: Allocator) Config {
        return Config{
            .config_parsed = parsed,
            .allocator = allocator,
        };
    }

    pub fn applyConfig(self: *Config) !?Error {
        const strategy_hash = std.StringHashMap(Strategy).init(self.allocator);
        const build = try Builder.init(self.allocator, self.config_parsed);

        self.conf = Conf{
            .root = build.root,
            .routes = build.routes,
            .strategy_hash = strategy_hash,
            .ssl = build.ssl,
        };

        var it = self.conf.routes.iterator();
        while (it.next()) |e| {
            const strategy = e.value_ptr.routeSetup() catch |err| {
                if (err == error.UnsupportedStrategy) {
                    var buffer: [1024]u8 = undefined;
                    const message = try std.fmt.bufPrint(&buffer, "Error: Unsupported strategy '{s}' in route '{s}'\n", .{
                        e.value_ptr.strategy,
                        e.key_ptr.*,
                    });
                    return Error{
                        .err_message = message,
                    };
                }
                return err;
            };
            const strategy_init = try strategy.init(e.value_ptr.backends, self.allocator);
            try self.conf.strategy_hash.put(e.key_ptr.*, strategy_init); // Add to hashmap
        }

        return null;
    }

    pub fn deinit(self: *Config) void {
        self.deinitBuilder();
        self.deinitStrategies();
    }

    pub fn deinitStrategies(self: *Config) void {
        var it = self.conf.strategy_hash.iterator();
        while (it.next()) |e| {
            e.value_ptr.round_robin.backends.deinit();
        }
        self.conf.strategy_hash.deinit();
    }

    pub fn deinitBuilder(self: *Config) void {
        var it = self.conf.routes.iterator();

        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.backends);
        }

        self.conf.routes.deinit();

        if (self.conf.ssl) |s| {
            ssl_struct.deinit(@constCast(s));
        }
    }
};
