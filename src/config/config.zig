const std = @import("std");

const core = @import("core");

const Strategy = @import("../load_balancer/Strategy.zig").Strategy;
const Route = @import("../load_balancer/route.zig").Route;
const Builder = @import("../config/config_builder.zig").Builder;
const Shared_Config = @import("../shared_memory/SharedMemory.zig").SharedMemory([4096]u8);
const RouteMemory = @import("../shared_memory/RouteMemory.zig");

const Allocator = std.mem.Allocator;
const JsonParsedValue = std.json.Parsed(std.json.Value);

const ssl = core.SSL;
const Epoll = core.Epoll;

pub const Conf = struct {
    root: []const u8,
    routes: std.StringHashMap(Route),
    strategy_hash: std.StringHashMap(Strategy) = undefined,
    ssl: ?*ssl.SSL_CTX,
    ssl_certificate: []const u8 = "",
    ssl_certificate_key: []const u8 = "",
    security: bool,
};

pub const ValidationMessage = struct {
    err_message: ?[]const u8 = null,
    conf: ?Conf = null,
};

pub const Config = struct {
    config_parsed: JsonParsedValue,
    allocator: Allocator,
    conf: Conf = undefined,
    version: usize,

    pub fn init(
        json_data: []u8,
        allocator: Allocator,
        writer: ?std.net.Stream.Writer,
        version: usize,
        create: bool,
    ) !Config {
        const parsed = std.json.parseFromSlice(std.json.Value, allocator, json_data, .{}) catch |err| {
            if (writer) |w| {
                var buf_m: [1024]u8 = undefined;
                const err_message = try std.fmt.bufPrint(&buf_m, "Invaild Config, '{s}'", .{@errorName(err)});
                _ = try w.write(err_message);
                return err;
            }
            return err;
        };
        errdefer parsed.deinit();

        const response = applyConfig(parsed, allocator, version, create) catch |err| {
            if (writer) |w| {
                var buf_m: [1024]u8 = undefined;
                const err_message = try std.fmt.bufPrint(&buf_m, "Invaild json, '{s}'", .{@errorName(err)});
                _ = try w.write(err_message);
                return err;
            }
            return err;
        };

        if (response.conf == null) {
            if (writer) |w| {
                var buf_m: [1024]u8 = undefined;
                const err_message = try std.fmt.bufPrint(&buf_m, "Invaild json, '{s}'", .{response.err_message.?});
                _ = try w.write(err_message);
            } else {
                std.log.err("{s}", .{response.err_message.?});
            }
            return error.UnsupportedStrategy;
        }

        return Config{
            .config_parsed = parsed,
            .allocator = allocator,
            .conf = response.conf.?,
            .version = version,
        };
    }

    pub fn share(shared_memory: Shared_Config, version: usize, data: []u8) !void {
        var buffer: [4096]u8 = undefined;

        const config_data = try std.fmt.bufPrint(&buffer, "{d}|{s}", .{ version, data[0..data.len] });
        shared_memory.writeStringData(buffer[0..config_data.len]);
    }

    pub fn deinit(self: *Config) void {
        self.deinitBuilder();
        self.deinitStrategies();
        self.config_parsed.deinit();
    }

    pub fn deinitStrategies(self: *Config) void {
        var it = self.conf.strategy_hash.iterator();
        while (it.next()) |e| {
            e.value_ptr.deinit();
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
            ssl.deinit(s);
        }
    }

    pub fn deinitMemory(self: Config) void {
        var it = self.conf.routes.iterator();
        while (it.next()) |entry| {
            RouteMemory.deleteMemoryRoute(entry.key_ptr.*, self.version) catch {};
        }
    }

    fn applyConfig(
        config_parsed: JsonParsedValue,
        allocator: Allocator,
        version: usize,
        create: bool,
    ) !ValidationMessage {
        var strategy_hash = std.StringHashMap(Strategy).init(allocator);
        errdefer strategy_hash.deinit();
        const build = try Builder.init(allocator, config_parsed, version, create);

        var it = build.routes.iterator();
        while (it.next()) |e| {
            const strategy = e.value_ptr.routeSetup() catch |err| {
                if (err == error.UnsupportedStrategy) {
                    var buffer: [1024]u8 = undefined;
                    const message = try std.fmt.bufPrint(&buffer, "Error: Unsupported strategy '{s}' in route '{s}'\n", .{
                        e.value_ptr.strategy,
                        e.key_ptr.*,
                    });
                    return ValidationMessage{
                        .err_message = message,
                    };
                }
                return err;
            };
            const strategy_init = try strategy.init(e.value_ptr.backends, allocator, e.key_ptr.*, version);
            try strategy_hash.put(e.key_ptr.*, strategy_init);
        }

        return ValidationMessage{
            .conf = .{
                .root = build.root,
                .routes = build.routes,
                .strategy_hash = strategy_hash,
                .ssl = build.ssl,
                .ssl_certificate = build.ssl_certificate,
                .ssl_certificate_key = build.ssl_certificate_key,
                .security = build.security,
            },
        };
    }
};
