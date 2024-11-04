const std = @import("std");
const ssl_struc = @import("../ssl/SSL.zig");
const r = @import("../load_balancer/route.zig");

const Route = r.Route;
const Backend = r.Backend;

/// Builder for step-by-step construction of Config
pub const Builder = struct {
    allocator: std.mem.Allocator,
    root: []const u8 = undefined,
    routes: std.StringHashMap(Route) = undefined,
    ssl: ?*ssl_struc.SSL_CTX,
    ssl_certificate: []const u8 = "",
    ssl_certificate_key: []const u8 = "",

    pub fn init(allocator: std.mem.Allocator, parsed: std.json.Parsed(std.json.Value)) !Builder {
        var hash_map = std.StringHashMap(Route).init(allocator);
        errdefer hash_map.deinit(); // Free `hash_map` if an error occurs

        const root = parsed.value.object.get("root") orelse return error.MissingRootField;
        const routes = parsed.value.object.get("routes") orelse return error.MissingRoutesField;
        const ssl = parsed.value.object.get("ssl");

        const root_value = try validateRoot(root);

        // SSL context initialization
        const valid_ssl = try validateSSL(ssl);

        // If validateRoutes fails, `hash_map` will be deallocated by the errdefer above
        try validateRoutes(routes, &hash_map, allocator);

        return Builder{
            .allocator = allocator,
            .root = root_value,
            .routes = hash_map,
            .ssl = valid_ssl.ssl_ctx,
            .ssl_certificate = valid_ssl.ssl_certificate,
            .ssl_certificate_key = valid_ssl.ssl_certificate_key,
        };
    }

    const Valid_SSL = struct {
        ssl_ctx: ?*ssl_struc.SSL_CTX,
        ssl_certificate: []const u8,
        ssl_certificate_key: []const u8,
    };

    fn validateSSL(ssl_value: ?std.json.Value) !Valid_SSL {
        if (ssl_value) |s_v| {
            switch (s_v) {
                .object => |ssl| {
                    const cert = ssl.get("ssl_certificate") orelse return error.MissingCertificate;
                    const key = ssl.get("ssl_certificate_key") orelse return error.MissingCertificatePrivateKey;
                    const cert_path = try validateCertificate(cert);
                    const cert_key_path = try validateCertificateKey(key);
                    const ssl_ctx = try ssl_struc.initializeSSLContext(cert_path, cert_key_path);

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

    fn validateRoutes(routes_value: std.json.Value, hash_map: *std.StringHashMap(Route), allocator: std.mem.Allocator) !void {
        switch (routes_value) {
            .object => |routes_obj| {
                var it = routes_obj.iterator();
                var has_main_route = false;

                while (it.next()) |entry| {
                    if (hash_map.get(entry.key_ptr.*) != null) return error.DuplicateRoute;
                    const route = try validateRoute(entry.value_ptr.*, allocator);
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
                if (backends_array.items.len == 0) return error.EmptyBackendsArray;
                var backends = try allocator.alloc(Backend, backends_array.items.len);
                for (backends_array.items, 0..) |backend_value, i| {
                    backends[i] = try validateBackend(backend_value);
                }
                return backends;
            },
            else => return error.InvalidBackendsArray,
        }
    }
};
