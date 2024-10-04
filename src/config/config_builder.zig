const std = @import("std");
const r = @import("../load_balancer/route.zig");

const Route = r.Route;
const Backend = r.Backend;

/// Builder for step-by-step construction of Config
pub const Builder = struct {
    allocator: std.mem.Allocator,
    root: []const u8 = undefined,
    routes: std.StringHashMap(Route) = undefined,

    pub fn init(allocator: std.mem.Allocator, root: std.json.Value, routes: std.json.Value) !Builder {
        var hash_map = std.StringHashMap(Route).init(allocator);

        const root_value = try validateRoot(root);
        try validateRoutes(routes, &hash_map, allocator);

        return Builder{
            .allocator = allocator,
            .root = root_value,
            .routes = hash_map,
        };
    }

    fn validateRoot(root_value: std.json.Value) ![]const u8 {
        switch (root_value) {
            .string => |root_str| return root_str,
            else => return error.InvalidRootType,
        }
    }

    fn validateRoutes(routes_value: std.json.Value, hash_map: *std.StringHashMap(Route), allocator: std.mem.Allocator) !void {
        switch (routes_value) {
            .object => |routes_obj| {
                var it = routes_obj.iterator();
                while (it.next()) |entry| {
                    const route = try validateRoute(entry.value_ptr.*, allocator);
                    try hash_map.put(entry.key_ptr.*, route);
                }
            },
            else => return error.InvalidRoutesField,
        }
    }
    fn validateRoute(route_value: std.json.Value, allocator: std.mem.Allocator) !Route {
        switch (route_value) {
            .object => |route_obj| {
                const backends_value = route_obj.get("backends") orelse return error.MissingBackendsField;
                const strategy_value = route_obj.get("strategy");

                const backends = try validateBackends(backends_value, allocator);

                if (strategy_value) |s_v| {
                    const strategy = try validateStrategy(s_v);

                    return Route{
                        .backends = backends,
                        .strategy = strategy,
                    };
                }
                return Route{
                    .backends = backends,
                };
            },
            else => return error.InvalidRouteStructure,
        }
    }

    fn validateStrategy(strategy_value: std.json.Value) ![]const u8 {
        switch (strategy_value) {
            .string => |strategy_str| {
                return strategy_str;
            },
            else => return error.InvalidStrategy,
        }
    }

    fn validateHost(host_value: std.json.Value) ![]const u8 {
        switch (host_value) {
            .string => |host_str| {
                return host_str;
            },
            else => return error.InvalidBackendHost,
        }
    }

    fn validateMaxFailure(max_failure_value: std.json.Value) !i64 {
        switch (max_failure_value) {
            .integer => |max_fail_int| {
                return max_fail_int;
            },
            else => return error.InvalidBackendMaxFailure,
        }
    }
    fn validateBackend(backend: std.json.Value) !Backend {
        switch (backend) {
            .object => |backend_obj| {
                const host = backend_obj.get("host") orelse return error.MissingBackendHost;
                const max_failure = backend_obj.get("max_failure");

                const host_str = try validateHost(host);
                if (max_failure) |failure| {
                    const max_fail_int = try validateMaxFailure(failure);
                    return Backend{
                        .host = host_str,
                        .max_failure = @intCast(max_fail_int),
                    };
                }
                return Backend{
                    .host = host_str,
                };
            },
            else => return error.InvalidBackendStructure,
        }
    }

    fn validateBackends(backends_value: std.json.Value, allocator: std.mem.Allocator) ![]Backend {
        switch (backends_value) {
            .array => |backends_array| {
                var backends = try allocator.alloc(Backend, backends_array.items.len);
                for (backends_array.items, 0..) |backend_value, i| {
                    backends[i] = try validateBackend(backend_value);
                }
                return backends;
            },
            else => return error.InvalidBackendsArray,
        }
    }

    /// Finalize and return the validated config
    pub fn build(self: Builder) void {
        std.debug.print("Root is {s}", .{self.root});
        var it = self.routes.iterator();
        while (it.next()) |value| {
            std.debug.print("routes: key:=> {s} and backends:=> {any} and strategy :=> {d}\n", .{ value.key_ptr.*, value.value_ptr.*.backends, value.value_ptr.strategy });
        }
    }
};
