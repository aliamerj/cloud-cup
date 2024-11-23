const std = @import("std");
const ssl = @import("core").SSL;
const r = @import("route.zig");
const Backend = @import("common").Backend;
const RouteMemory = @import("common").RouteMemory;

const Route = r.Route;
const strategies = r.strategies_supported;

/// Builder for step-by-step construction of Config
pub const Builder = struct {
    allocator: std.mem.Allocator,
    root: []const u8 = undefined,
    routes: std.StringHashMap(Route) = undefined,
    ssl: ?*ssl.SSL_CTX,
    ssl_certificate: []const u8 = "",
    ssl_certificate_key: []const u8 = "",
    security: bool,
    version: usize,

    pub fn init(
        allocator: std.mem.Allocator,
        parsed: std.json.Parsed(std.json.Value),
        version: usize,
        create: bool,
    ) !Builder {
        var hash_map = std.StringHashMap(Route).init(allocator);
        errdefer hash_map.deinit(); // Free `hash_map` if an error occurs

        const root = parsed.value.object.get("root") orelse return error.MissingRootField;
        const routes = parsed.value.object.get("routes") orelse return error.MissingRoutesField;
        const ssl_obj = parsed.value.object.get("ssl");
        const security = parsed.value.object.get("security");

        const root_value = try validateRoot(root);
        const security_value = try validateSecurity(security);
        const valid_ssl = try validateSSL(ssl_obj);

        var all_backend = std.ArrayList([]Backend).init(allocator);
        defer all_backend.deinit();

        // If validateRoutes fails, `hash_map` will be deallocated by the errdefer above
        validateRoutes(routes, &hash_map, allocator, &all_backend, version, create) catch |e| {
            for (all_backend.items) |b| {
                allocator.free(b);
            }
            return e;
        };

        return Builder{
            .allocator = allocator,
            .root = root_value,
            .routes = hash_map,
            .ssl = valid_ssl.ssl_ctx,
            .ssl_certificate = valid_ssl.ssl_certificate,
            .ssl_certificate_key = valid_ssl.ssl_certificate_key,
            .security = security_value,
            .version = version,
        };
    }

    pub fn deinit(self: *Builder) void {
        var it = self.routes.iterator();

        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.backends);
            RouteMemory.deleteMemoryRoute(entry.key_ptr.*, self.version) catch {};
        }

        self.routes.deinit();

        if (self.ssl) |s| {
            ssl.deinit(s);
        }
    }

    const Valid_SSL = struct {
        ssl_ctx: ?*ssl.SSL_CTX,
        ssl_certificate: []const u8,
        ssl_certificate_key: []const u8,
    };

    fn validateSecurity(security_value: ?std.json.Value) !bool {
        if (security_value) |sec_value| {
            switch (sec_value) {
                .bool => |sec| return sec,
                else => return error.InvalidSecurityType,
            }
        }
        return false;
    }

    fn validateSSL(ssl_value: ?std.json.Value) !Valid_SSL {
        if (ssl_value) |s_v| {
            switch (s_v) {
                .object => |ss| {
                    const cert = ss.get("ssl_certificate") orelse return error.MissingCertificate;
                    const key = ss.get("ssl_certificate_key") orelse return error.MissingCertificatePrivateKey;
                    const cert_path = try validateCertificate(cert);
                    const cert_key_path = try validateCertificateKey(key);

                    const ssl_ctx = try ssl.initializeSSLContext(cert_path, cert_key_path);

                    return Valid_SSL{
                        .ssl_ctx = ssl_ctx,
                        .ssl_certificate = cert_path,
                        .ssl_certificate_key = cert_key_path,
                    };
                },
                else => return error.InvalidSSLConfig,
            }
        }
        return Valid_SSL{
            .ssl_ctx = null,
            .ssl_certificate = "",
            .ssl_certificate_key = "",
        };
    }

    fn validateCertificate(cert_value: std.json.Value) ![]const u8 {
        switch (cert_value) {
            .string => |cert_str| return cert_str,
            else => return error.InvalidCertificateType,
        }
    }

    fn validateCertificateKey(cert_key_value: std.json.Value) ![]const u8 {
        switch (cert_key_value) {
            .string => |cert_key_str| return cert_key_str,
            else => return error.InvalidCertificatePrivateKeyType,
        }
    }

    fn validateRoot(root_value: std.json.Value) ![]const u8 {
        switch (root_value) {
            .string => |root_str| return root_str,
            else => return error.InvalidRootType,
        }
    }

    fn validateRoutes(
        routes_value: std.json.Value,
        hash_map: *std.StringHashMap(Route),
        allocator: std.mem.Allocator,
        all_backends: *std.ArrayList([]Backend),
        version: usize,
        create: bool,
    ) !void {
        switch (routes_value) {
            .object => |routes_obj| {
                var it = routes_obj.iterator();
                var has_main_route = false;

                while (it.next()) |entry| {
                    if (hash_map.get(entry.key_ptr.*) != null) return error.DuplicateRoute;
                    const route = try validateRoute(
                        entry.key_ptr.*,
                        entry.value_ptr.*,
                        allocator,
                        all_backends,
                        version,
                        create,
                    );
                    if (std.mem.eql(u8, entry.key_ptr.*, "*")) has_main_route = true;
                    if (entry.key_ptr.*.len > 1 and std.mem.endsWith(u8, entry.key_ptr.*, "/")) return error.InvalidRouteEndWith;
                    try hash_map.put(entry.key_ptr.*, route);
                }

                if (!has_main_route) {
                    return error.MissingMainRoute;
                }
            },
            else => return error.InvalidRoutesField,
        }
    }
    fn validateRoute(
        route_key: []const u8,
        route_value: std.json.Value,
        allocator: std.mem.Allocator,
        all_backends: *std.ArrayList([]Backend),
        version: usize,
        create: bool,
    ) !Route {
        switch (route_value) {
            .object => |route_obj| {
                const backends_value = route_obj.get("backends") orelse return error.MissingBackendsField;
                const strategy_value = route_obj.get("strategy");

                const backends = try validateBackends(backends_value, allocator);
                try all_backends.append(backends);

                if (create) {
                    try RouteMemory.createRouteMemory(route_key, version);
                }

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
                for (strategies) |strategy| {
                    if (std.mem.eql(u8, strategy_str, strategy)) {
                        return strategy;
                    }
                }

                return error.UnsupportedStrategy;
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
                if (backends_array.items.len == 0) return error.EmptyBackendsArray;
                var backends = try allocator.alloc(Backend, backends_array.items.len);
                errdefer allocator.free(backends);
                for (backends_array.items, 0..) |backend_value, i| {
                    backends[i] = try validateBackend(backend_value);
                }
                return backends;
            },
            else => return error.InvalidBackendsArray,
        }
    }
};

test "Builder init with valid config" {
    std.testing.refAllDecls(@This());

    const allocator = std.testing.allocator;

    const valid_json = "{\"root\": \"127.0.0.1:8080\"," ++ "\"routes\": {" ++ "\"*\": {\"backends\": [{\"host\": \"127.0.0.1:8081\",\"max_failure\": 5}]}," ++ "\"/\": {\"backends\": [" ++ "{\"host\": \"127.0.0.1:8082\",\"max_failure\": 2}," ++ "{\"host\": \"127.0.0.1:8083\",\"max_failure\": 10}]}" ++ "}}";

    // Parse the valid JSON
    const config = try std.json.parseFromSlice(std.json.Value, allocator, valid_json, .{});
    defer config.deinit();

    // Initialize the Builder
    var conf = try Builder.init(allocator, config, 1, false);
    defer conf.deinit();

    // Validate root
    try std.testing.expectEqualStrings(conf.root, "127.0.0.1:8080");

    // Validate version
    try std.testing.expectEqual(conf.version, 1);

    // Validate routes
    const main_route = conf.routes.get("*").?;
    try std.testing.expectEqual(main_route.backends.len, 1);
    try std.testing.expectEqualStrings(main_route.backends[0].host, "127.0.0.1:8081");
    try std.testing.expectEqual(main_route.backends[0].max_failure, 5);

    const slash_route = conf.routes.get("/").?;
    try std.testing.expectEqual(slash_route.backends.len, 2);
    try std.testing.expectEqualStrings(slash_route.backends[0].host, "127.0.0.1:8082");
    try std.testing.expectEqual(slash_route.backends[0].max_failure, 2);
    try std.testing.expectEqualStrings(slash_route.backends[1].host, "127.0.0.1:8083");
    try std.testing.expectEqual(slash_route.backends[1].max_failure, 10);

    // Validate security setting (default to false)
    try std.testing.expect(!conf.security);

    // Validate SSL configuration (should be null in this case)
    try std.testing.expect(conf.ssl == null);
}

test "Builder init with invalid Root" {
    const allocator = std.testing.allocator;

    // Missing `root`
    const missing_root_json = "{ \"routes\": {\"/\": {\"backends\": [{\"host\": \"127.0.0.1:8081\",\"max_failure\": 2}]}}}";
    const config_missing_root = try std.json.parseFromSlice(std.json.Value, allocator, missing_root_json, .{});
    defer config_missing_root.deinit();

    const err_missing_root = Builder.init(allocator, config_missing_root, 1, false) catch |err| err;
    try std.testing.expectEqual(err_missing_root, error.MissingRootField);

    // invalid `root`
    const invaild_root_json = "{\"root\":12345, \"routes\": {\"/\": {\"backends\": [{\"host\": \"127.0.0.1:8081\",\"max_failure\": 2}]}}}";
    const invalid_root = try std.json.parseFromSlice(std.json.Value, allocator, invaild_root_json, .{});
    defer invalid_root.deinit();
    const err_invalid_root = Builder.init(allocator, invalid_root, 1, false) catch |err| err;
    try std.testing.expectEqual(err_invalid_root, error.InvalidRootType);
}

test "Builder int with invalid routes" {
    const allocator = std.testing.allocator;

    // missing routes field
    const missing_routes_json = "{\"root\": \"127.0.0.1:8080\"}";
    const config_missing_routes = try std.json.parseFromSlice(std.json.Value, allocator, missing_routes_json, .{});
    defer config_missing_routes.deinit();
    const err_missing_routes = Builder.init(allocator, config_missing_routes, 1, false) catch |err| err;
    try std.testing.expectEqual(err_missing_routes, error.MissingRoutesField);

    // invalid routes type
    const invalid_routes_json = "{\"root\": \"127.0.0.1:8080\", \"routes\": 12345}";
    const config_invalid_routes = try std.json.parseFromSlice(std.json.Value, allocator, invalid_routes_json, .{});
    defer config_invalid_routes.deinit();
    const err_invalid_routes = Builder.init(allocator, config_invalid_routes, 1, false) catch |err| err;
    try std.testing.expectEqual(err_invalid_routes, error.InvalidRoutesField);

    // missing main route *
    const missing_main_route_json = "{\"root\": \"127.0.0.1:8080\", \"routes\": {\"/test\": {\"backends\": [{\"host\": \"127.0.0.1:8081\",\"max_failure\": 2}]}}}";
    const config_missing_main_route = try std.json.parseFromSlice(std.json.Value, allocator, missing_main_route_json, .{});
    defer config_missing_main_route.deinit();
    const err_missing_main_route = Builder.init(allocator, config_missing_main_route, 1, false) catch |err| err;
    try std.testing.expectEqual(err_missing_main_route, error.MissingMainRoute);

    //  Invalid Route Ending
    const invalid_route_end_json = "{\"root\": \"127.0.0.1:8080\", \"routes\": {\"/test/\": {\"backends\": [{\"host\": \"127.0.0.1:8081\",\"max_failure\": 2}]}, \"*\": {\"backends\": [{\"host\": \"127.0.0.1:8082\",\"max_failure\": 3}]}}}";
    const config_invalid_route_end = try std.json.parseFromSlice(std.json.Value, allocator, invalid_route_end_json, .{});
    defer config_invalid_route_end.deinit();
    const err_invalid_route_end = Builder.init(allocator, config_invalid_route_end, 1, false) catch |err| err;
    try std.testing.expectEqual(err_invalid_route_end, error.InvalidRouteEndWith);

    // Unsupported Strategy
    const invalid_strategy_json = "{\"root\": \"127.0.0.1:8080\", \"routes\": {\"/\": {\"backends\": [{\"host\": \"127.0.0.1:8081\",\"max_failure\": 2}], \"strategy\":\"Unsupported\"}, \"*\": {\"backends\": [{\"host\": \"127.0.0.1:8082\",\"max_failure\": 3}]}}}";
    const config_invalid_strategy = try std.json.parseFromSlice(std.json.Value, allocator, invalid_strategy_json, .{});
    defer config_invalid_strategy.deinit();
    const err_invalid_strategy = Builder.init(allocator, config_invalid_strategy, 1, false) catch |err| err;
    try std.testing.expectEqual(err_invalid_strategy, error.UnsupportedStrategy);

    // valid routes
    const valid_routes_json = "{\"root\": \"127.0.0.1:8080\", \"routes\": {\"/\": {\"backends\": [{\"host\": \"127.0.0.1:8081\",\"max_failure\": 2}], \"strategy\":\"round-robin\"}, \"*\": {\"backends\": [{\"host\": \"127.0.0.1:8082\",\"max_failure\": 3}]}}}";
    const config_valid_routes = try std.json.parseFromSlice(std.json.Value, allocator, valid_routes_json, .{});
    defer config_valid_routes.deinit();
    var conf = try Builder.init(allocator, config_valid_routes, 1, false);
    defer conf.deinit();
    try std.testing.expectEqual(conf.routes.count(), 2);
}

test "Builder init with invalid backends" {
    const allocator = std.testing.allocator;

    // missing backends field in route
    const missing_backends_json = "{\"root\": \"127.0.0.1:8080\", \"routes\": {\"*\": {\"strategy\": \"round_robin\"}}}";
    const config_missing_backends = try std.json.parseFromSlice(std.json.Value, allocator, missing_backends_json, .{});
    defer config_missing_backends.deinit();
    const err_missing_backends = Builder.init(allocator, config_missing_backends, 1, false) catch |err| err;
    try std.testing.expectEqual(err_missing_backends, error.MissingBackendsField);

    // invalid backends type
    const invalid_backends_json = "{\"root\": \"127.0.0.1:8080\", \"routes\": {\"*\": {\"backends\": \"invalid_type\"}}}";
    const config_invalid_backends = try std.json.parseFromSlice(std.json.Value, allocator, invalid_backends_json, .{});
    defer config_invalid_backends.deinit();
    const err_invalid_backends = Builder.init(allocator, config_invalid_backends, 1, false) catch |err| err;
    try std.testing.expectEqual(err_invalid_backends, error.InvalidBackendsArray);

    // empty backends array
    const empty_backends_json = "{\"root\": \"127.0.0.1:8080\", \"routes\": {\"*\": {\"backends\": []}}}";
    const config_empty_backends = try std.json.parseFromSlice(std.json.Value, allocator, empty_backends_json, .{});
    defer config_empty_backends.deinit();
    const err_empty_backends = Builder.init(allocator, config_empty_backends, 1, false) catch |err| err;
    try std.testing.expectEqual(err_empty_backends, error.EmptyBackendsArray);

    //  invalid backend host
    const invalid_backend_json = "{\"root\": \"127.0.0.1:8080\", \"routes\": {\"*\": {\"backends\": [{\"host\": 12345}]}}}";
    const config_invalid_backend = try std.json.parseFromSlice(std.json.Value, allocator, invalid_backend_json, .{});
    defer config_invalid_backend.deinit();
    const err_invalid_backend = Builder.init(allocator, config_invalid_backend, 1, false) catch |err| err;
    try std.testing.expectEqual(err_invalid_backend, error.InvalidBackendHost);

    // invalid host backends
    const invalid_host_backend_json = "{\"root\": \"127.0.0.1:8080\", \"routes\": {\"*\": {\"backends\": [{\"host\": 12345, \"max_failure\": 3}]}}}";
    const config_invalid_host = try std.json.parseFromSlice(std.json.Value, allocator, invalid_host_backend_json, .{});
    defer config_invalid_host.deinit();
    const err_invalid_host = Builder.init(allocator, config_invalid_host, 1, false) catch |err| err;
    try std.testing.expectEqual(err_invalid_host, error.InvalidBackendHost);

    //  Invalid max_failure Type in Backend
    const invalid_max_failure_json = "{\"root\": \"127.0.0.1:8080\", \"routes\": {\"*\": {\"backends\": [{\"host\": \"127.0.0.1:8081\", \"max_failure\": \"invalid\"}]}}}";
    const config_invalid_max_failure = try std.json.parseFromSlice(std.json.Value, allocator, invalid_max_failure_json, .{});
    defer config_invalid_max_failure.deinit();

    const err_invalid_max_failure = Builder.init(allocator, config_invalid_max_failure, 1, false) catch |err| err;
    try std.testing.expectEqual(err_invalid_max_failure, error.InvalidBackendMaxFailure);

    //  Missing max_failure in Backend (Optional Field)
    const missing_max_failure_json = "{\"root\": \"127.0.0.1:8080\", \"routes\": {\"*\": {\"backends\": [{\"host\": \"127.0.0.1:8081\"}]}}}";
    const config_missing_max_failure = try std.json.parseFromSlice(std.json.Value, allocator, missing_max_failure_json, .{});
    defer config_missing_max_failure.deinit();
    var confi = try Builder.init(allocator, config_missing_max_failure, 1, false);
    defer confi.deinit();
    // No error should be raised, as max_failure is optional
    try std.testing.expectEqualStrings(confi.routes.get("*").?.backends[0].host, "127.0.0.1:8081");

    // Valid Backend with host and max_failure
    const valid_backend_json = "{\"root\": \"127.0.0.1:8080\", \"routes\": {\"*\": {\"backends\": [{\"host\": \"127.0.0.1:8081\", \"max_failure\": 3}]}}}";
    const config_valid_backend = try std.json.parseFromSlice(std.json.Value, allocator, valid_backend_json, .{});
    defer config_valid_backend.deinit();
    var conf = try Builder.init(allocator, config_valid_backend, 1, false);
    defer conf.deinit();
    try std.testing.expectEqualStrings(conf.routes.get("*").?.backends[0].host, "127.0.0.1:8081");
    try std.testing.expectEqual(conf.routes.get("*").?.backends[0].max_failure, 3);
}

test "Builder init with invalid SSL object structure" {
    const allocator = std.testing.allocator;

    // Invalid SSL Object Structure
    const invalid_ssl_json = "{\"root\": \"127.0.0.1:8080\",\"ssl\": 1234, \"routes\": {\"*\": {\"backends\": [{\"host\": \"127.0.0.1:8081\", \"max_failure\": 3}]}}}";
    const config_invalid_ssl = try std.json.parseFromSlice(std.json.Value, allocator, invalid_ssl_json, .{});
    defer config_invalid_ssl.deinit();
    const err_invalid_ssl = Builder.init(allocator, config_invalid_ssl, 1, false) catch |err| err;
    try std.testing.expectEqual(err_invalid_ssl, error.InvalidSSLConfig);

    // Missing SSL Certificate
    const missing_cert_json = "{\"root\": \"127.0.0.1:8080\",\"ssl\": {\"ssl_certificate_key\": \"path/to/key\"}, \"routes\": {\"*\": {\"backends\": [{\"host\": \"127.0.0.1:8081\", \"max_failure\": 3}]}}}";
    const config_missing_cert = try std.json.parseFromSlice(std.json.Value, allocator, missing_cert_json, .{});
    defer config_missing_cert.deinit();
    const err_missing_cert = Builder.init(allocator, config_missing_cert, 1, false) catch |err| err;
    try std.testing.expectEqual(err_missing_cert, error.MissingCertificate);

    // Missing SSL Private Key
    const missing_key_json = "{\"root\": \"127.0.0.1:8080\",\"ssl\": {\"ssl_certificate\": \"path/to/cert\"}, \"routes\": {\"*\": {\"backends\": [{\"host\": \"127.0.0.1:8081\", \"max_failure\": 3}]}}}";
    const config_missing_key = try std.json.parseFromSlice(std.json.Value, allocator, missing_key_json, .{});
    defer config_missing_key.deinit();
    const err_missing_key = Builder.init(allocator, config_missing_key, 1, false) catch |err| err;
    try std.testing.expectEqual(err_missing_key, error.MissingCertificatePrivateKey);

    // Invalid SSL Certificate Type
    const invalid_cert_type_json = "{\"root\": \"127.0.0.1:8080\",\"ssl\": {\"ssl_certificate\": 12345, \"ssl_certificate_key\": \"path/to/key\"}, \"routes\": {\"*\": {\"backends\": [{\"host\": \"127.0.0.1:8081\", \"max_failure\": 3}]}}}";
    const config_invalid_cert_type = try std.json.parseFromSlice(std.json.Value, allocator, invalid_cert_type_json, .{});
    defer config_invalid_cert_type.deinit();
    const err_invalid_cert_type = Builder.init(allocator, config_invalid_cert_type, 1, false) catch |err| err;
    try std.testing.expectEqual(err_invalid_cert_type, error.InvalidCertificateType);

    //  Invalid SSL Certificate Private Key Type
    const invalid_key_type_json = "{\"root\": \"127.0.0.1:8080\",\"ssl\":  {\"ssl_certificate\": \"path/to/cert\", \"ssl_certificate_key\": 12345}, \"routes\": {\"*\": {\"backends\": [{\"host\": \"127.0.0.1:8081\", \"max_failure\": 3}]}}}";
    const config_invalid_key_type = try std.json.parseFromSlice(std.json.Value, allocator, invalid_key_type_json, .{});
    defer config_invalid_key_type.deinit();
    const err_invalid_key_type = Builder.init(allocator, config_invalid_key_type, 1, false) catch |err| err;
    try std.testing.expectEqual(err_invalid_key_type, error.InvalidCertificatePrivateKeyType);

    // Valid SSL Configuration with Certificate and Private Key
    const valid_json = "{\"root\": \"127.0.0.1:8080\",\"ssl\":  {\"ssl_certificate\": \"path/to/cert\", \"ssl_certificate_key\": \"path/to/key\"}, \"routes\": {\"*\": {\"backends\": [{\"host\": \"127.0.0.1:8081\", \"max_failure\": 3}]}}}";
    const config_valid = try std.json.parseFromSlice(std.json.Value, allocator, valid_json, .{});
    defer config_valid.deinit();
    const err_v = Builder.init(allocator, config_valid, 1, false) catch |err| err;
    try std.testing.expectEqual(err_v, error.FileNotFound);
}
