const std = @import("std");
const Strategy = @import("../load_balancer/Strategy.zig").Strategy;
const Epoll = @import("../http/epoll_handler.zig").Epoll;
const Route = @import("../load_balancer/route.zig").Route;
const Builder = @import("../config/config_builder.zig").Builder;

const Allocator = std.mem.Allocator;

pub const Config = struct {
    root: []const u8,
    routes: std.StringHashMap(Route),
    allocator: Allocator,

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

    pub fn deinitBuilder(self: *Config) void {
        var it = self.routes.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.backends);
        }
        self.routes.deinit();
    }
};
