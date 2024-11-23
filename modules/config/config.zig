const std = @import("std");
const core = @import("core");
const common = @import("common");

const Strategy = @import("loadBalancer").Strategy;
const Route = @import("route.zig").Route;
const Builder = @import("config_builder.zig").Builder;

const Allocator = std.mem.Allocator;
const JsonParsedValue = std.json.Parsed(std.json.Value);

const ssl = core.SSL;
const Epoll = core.Epoll;
const RouteMemory = common.RouteMemory;
const SharedConfig = common.SharedConfig;

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

        const conf = applyConfig(parsed, allocator, version, create) catch |err| {
            if (writer) |w| {
                var buf_m: [1024]u8 = undefined;
                const err_message = try std.fmt.bufPrint(&buf_m, "Invaild json, '{s}'", .{@errorName(err)});
                _ = try w.write(err_message);
                return err;
            }
            return err;
        };

        return Config{
            .config_parsed = parsed,
            .allocator = allocator,
            .conf = conf,
            .version = version,
        };
    }

    pub fn share(shared_memory: SharedConfig, version: usize, data: []u8) !void {
        var buffer: [4096]u8 = undefined;
        const config_data = try std.fmt.bufPrint(&buffer, "{d}|{s}", .{ version, data[0..data.len] });
        shared_memory.writeStringData(buffer[0..config_data.len]);
    }

    pub fn deinit(self: *Config) void {
        self.deinitMemory();
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
    ) !Conf {
        var strategy_hash = std.StringHashMap(Strategy).init(allocator);
        errdefer strategy_hash.deinit();
        var build = try Builder.init(allocator, config_parsed, version, create);
        errdefer build.deinit();

        var it = build.routes.iterator();
        while (it.next()) |e| {
            const strategy = e.value_ptr.routeSetup();
            const strategy_init = try strategy.init(e.value_ptr.backends, allocator, e.key_ptr.*, version);
            try strategy_hash.put(e.key_ptr.*, strategy_init);
        }

        return Conf{
            .root = build.root,
            .routes = build.routes,
            .strategy_hash = strategy_hash,
            .ssl = build.ssl,
            .ssl_certificate = build.ssl_certificate,
            .ssl_certificate_key = build.ssl_certificate_key,
            .security = build.security,
        };
    }
};

test "applyConfig - valid configuration" {
    const allocator = std.testing.allocator;

    const valid_json = "{\"root\": \"127.0.0.1:8080\"," ++ "\"routes\": {" ++ "\"*\": {\"backends\": [{\"host\": \"127.0.0.1:8081\",\"max_failure\": 5}]}," ++ "\"/\": {\"backends\": [" ++ "{\"host\": \"127.0.0.1:8082\",\"max_failure\": 2}," ++ "{\"host\": \"127.0.0.1:8083\",\"max_failure\": 10}]}" ++ "}}";
    const json = try std.fmt.allocPrint(allocator, "{s}", .{valid_json});
    defer allocator.free(json);

    var config = try Config.init(json[0..], allocator, null, 1, true);
    defer config.deinit();

    try std.testing.expect(config.version == 1);
    try std.testing.expectEqualStrings(config.conf.root, "127.0.0.1:8080");
}

test "applyConfig - missing required fields" {
    const allocator = std.testing.allocator;

    const missing_field_json = "{\"routes\": {\"/\": {\"backends\": [{\"host\": \"127.0.0.1:8082\"}]}}}"; // Missing root field
    const json = try std.fmt.allocPrint(allocator, "{s}", .{missing_field_json});
    defer allocator.free(json);

    const err_config = Config.init(json[0..], allocator, null, 1, true) catch |err| err;
    try std.testing.expect(err_config == error.MissingRootField);
}

test "Config  - invalid JSON data" {
    const allocator = std.testing.allocator;

    const fake_json = "fake json"; // Missing root field
    const json = try std.fmt.allocPrint(allocator, "{s}", .{fake_json});
    defer allocator.free(json);

    const err_config = Config.init(json, allocator, null, 1, true) catch |err| err;
    try std.testing.expect(err_config == error.SyntaxError);
}
