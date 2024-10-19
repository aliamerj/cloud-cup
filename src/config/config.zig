const std = @import("std");
const Strategy = @import("../load_balancer/Strategy.zig").Strategy;
const Epoll = @import("../http/epoll_handler.zig").Epoll;
const Route = @import("../load_balancer/route.zig").Route;
const Builder = @import("../config/config_builder.zig").Builder;
const Error = @import("../utils/error_channel.zig").Error;

const Allocator = std.mem.Allocator;

pub const Config = struct {
    root: []const u8,
    routes: std.StringHashMap(Route),
    allocator: Allocator,
    strategy_hash: std.StringHashMap(Strategy) = undefined,

    pub fn init(json_file_path: []const u8, allocator: Allocator) !Config {

        // Read the JSON file contents
        const data = try std.fs.cwd().readFileAlloc(allocator, json_file_path, 8024);
        defer allocator.free(data);

        // Parse the JSON data
        const parse = try std.json.parseFromSlice(std.json.Value, allocator, data, .{ .allocate = .alloc_always });
        defer parse.deinit();

        // Get the fields
        const root_value = parse.value.object.get("root") orelse return error.MissingRootField;
        const routes_value = parse.value.object.get("routes") orelse return error.MissingRoutesField;

        const build = try Builder.init(allocator, root_value, routes_value);

        return Config{
            .root = build.root,
            .routes = build.routes,
            .allocator = allocator,
        };
    }

    pub fn applyConfig(self: *Config) !?Error {
        errdefer self.deinitStrategies();
        self.strategy_hash = std.StringHashMap(Strategy).init(self.allocator);

        var it = self.routes.iterator();
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
            try self.strategy_hash.put(e.key_ptr.*, strategy_init);
        }

        return null;
    }

    pub fn deinitStrategies(self: *Config) void {
        var it = self.strategy_hash.iterator();
        while (it.next()) |e| {
            e.value_ptr.round_robin.backends.deinit();
        }
        self.strategy_hash.deinit();
    }

    pub fn deinitBuilder(self: *Config) void {
        self.deinitStrategies();
        var it = self.routes.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.backends);
        }
        self.routes.deinit();
    }
};
