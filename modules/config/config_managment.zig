const std = @import("std");
const ssl = @import("core").SSL;
const Config = @import("config.zig").Config;

const Atomic = std.atomic.Value;

pub const ConfigManager = struct {
    const Node = struct {
        data: Config,
    };

    allocator: std.mem.Allocator,
    head: Atomic(?*Node),

    pub fn init(allocator: std.mem.Allocator) ConfigManager {
        return ConfigManager{
            .allocator = allocator,
            .head = Atomic(?*Node).init(null),
        };
    }
    pub fn deinit(self: *ConfigManager) void {
        const head = self.head.load(.acquire) orelse unreachable;
        @constCast(&head.data).deinit();

        if (head.data.conf.ssl) |s| {
            ssl.deinit(s);
        }

        self.allocator.destroy(head);
    }

    pub fn pushNewConfig(self: *ConfigManager, config: Config) !void {
        const new_config = try self.allocator.create(Node);
        var head_ptr = self.head.load(.acquire);
        new_config.* = .{ .data = config };

        if (head_ptr) |old_config| {
            while (true) {
                const result = self.head.cmpxchgWeak(
                    old_config,
                    new_config,
                    .acquire,
                    .monotonic,
                );

                if (result != null) {
                    old_config.data.deinit();

                    if (old_config.data.conf.ssl) |s| {
                        ssl.deinit(s);
                    }
                    self.allocator.destroy(old_config);
                    break;
                }

                // Otherwise, reload the head_ptr and try again
                head_ptr = self.head.load(.acquire);
            }
            return;
        }

        self.head.store(new_config, .release);
    }

    pub fn getCurrentConfig(self: *ConfigManager) Config {
        const head = self.head.load(.acquire) orelse unreachable;
        return head.data;
    }
};

test "ConfigManager - Push and Retrieve Config" {
    const allocator = std.testing.allocator;

    const valid_json = "{\"root\": \"127.0.0.1:8080\"," ++ "\"routes\": {" ++ "\"*\": {\"backends\": [{\"host\": \"127.0.0.1:8081\",\"max_failure\": 5}]}," ++ "\"/\": {\"backends\": [" ++ "{\"host\": \"127.0.0.1:8082\",\"max_failure\": 2}," ++ "{\"host\": \"127.0.0.1:8083\",\"max_failure\": 10}]}" ++ "}}";
    const json = try std.fmt.allocPrint(allocator, "{s}", .{valid_json});
    defer allocator.free(json);

    const config = try Config.init(json[0..], allocator, null, 1, true);

    var manager = ConfigManager.init(allocator);
    defer manager.deinit();

    // Push the new config
    try manager.pushNewConfig(config);

    // Verify the current config matches the pushed one
    const current_config = manager.getCurrentConfig();
    try std.testing.expectEqualStrings(current_config.conf.root, config.conf.root);
}

test "ConfigManager - Push Multiple Configs with RCU" {
    const allocator = std.testing.allocator;

    var manager = ConfigManager.init(allocator);
    defer manager.deinit();

    // Push the first configuration
    const valid_json1 = "{\"root\": \"127.0.0.1:8080\"," ++ "\"routes\": {" ++ "\"*\": {\"backends\": [{\"host\": \"127.0.0.1:8081\",\"max_failure\": 5}]}," ++ "\"/\": {\"backends\": [" ++ "{\"host\": \"127.0.0.1:8082\",\"max_failure\": 2}," ++ "{\"host\": \"127.0.0.1:8083\",\"max_failure\": 10}]}" ++ "}}";
    const json_config1 = try std.fmt.allocPrint(allocator, "{s}", .{valid_json1});
    defer allocator.free(json_config1);

    const config1 = try Config.init(json_config1[0..], allocator, null, 1, true);
    try manager.pushNewConfig(config1);

    // Push the second configuration
    const valid_json2 = "{\"root\": \"127.0.0.1:8081\"," ++ "\"routes\": {" ++ "\"*\": {\"backends\": [{\"host\": \"127.0.0.1:8081\",\"max_failure\": 5}]}," ++ "\"/\": {\"backends\": [" ++ "{\"host\": \"127.0.0.1:8082\",\"max_failure\": 2}," ++ "{\"host\": \"127.0.0.1:8083\",\"max_failure\": 10}]}" ++ "}}";
    const json_config2 = try std.fmt.allocPrint(allocator, "{s}", .{valid_json2});
    defer allocator.free(json_config2);

    const config2 = try Config.init(json_config2[0..], allocator, null, 2, true);
    try manager.pushNewConfig(config2);

    // Verify the current config matches the most recent one
    const current_config = manager.getCurrentConfig();
    try std.testing.expectEqualStrings(current_config.conf.root, config2.conf.root);
}

test "ConfigManager - Concurrent Config Access with Threads" {
    const allocator = std.testing.allocator;

    var manager = ConfigManager.init(allocator);
    defer manager.deinit();

    // Push the first configuration
    const valid_json1 = "{\"root\": \"127.0.0.1:8080\"," ++ "\"routes\": {" ++ "\"*\": {\"backends\": [{\"host\": \"127.0.0.1:8081\",\"max_failure\": 5}]}," ++ "\"/\": {\"backends\": [" ++ "{\"host\": \"127.0.0.1:8082\",\"max_failure\": 2}," ++ "{\"host\": \"127.0.0.1:8083\",\"max_failure\": 10}]}" ++ "}}";
    const json_config1 = try std.fmt.allocPrint(allocator, "{s}", .{valid_json1});
    defer allocator.free(json_config1);

    const config1 = try Config.init(json_config1[0..], allocator, null, 1, true);
    try manager.pushNewConfig(config1);

    // Push the second configuration
    const valid_json2 = "{\"root\": \"127.0.0.1:8081\"," ++ "\"routes\": {" ++ "\"*\": {\"backends\": [{\"host\": \"127.0.0.1:8081\",\"max_failure\": 5}]}," ++ "\"/\": {\"backends\": [" ++ "{\"host\": \"127.0.0.1:8082\",\"max_failure\": 2}," ++ "{\"host\": \"127.0.0.1:8083\",\"max_failure\": 10}]}" ++ "}}";
    const json_config2 = try std.fmt.allocPrint(allocator, "{s}", .{valid_json2});
    defer allocator.free(json_config2);

    const config2 = try Config.init(json_config2[0..], allocator, null, 2, true);
    // Shared variable for result validation
    var result = Atomic(bool).init(false);

    // Spawn a thread to push a new configuration
    var push_thread = try std.Thread.spawn(.{ .allocator = allocator }, pushConfig, .{ &manager, config2 });

    // Spawn another thread to read the current configuration
    var read_thread = try std.Thread.spawn(.{ .allocator = allocator }, getConfig, .{ &manager, &result });

    // Wait for both threads to finish
    push_thread.join();
    read_thread.join();

    // Verify the result from the reading thread
    try std.testing.expect(result.load(.acquire));
}

test "ConfigManager - High Volume Concurrent Access" {
    const allocator = std.testing.allocator;

    var manager = ConfigManager.init(allocator);
    defer manager.deinit();
    // Push the first configuration
    const valid_json1 = "{\"root\": \"127.0.0.1:8080\"," ++ "\"routes\": {" ++ "\"*\": {\"backends\": [{\"host\": \"127.0.0.1:8081\",\"max_failure\": 5}]}," ++ "\"/\": {\"backends\": [" ++ "{\"host\": \"127.0.0.1:8082\",\"max_failure\": 2}," ++ "{\"host\": \"127.0.0.1:8083\",\"max_failure\": 10}]}" ++ "}}";
    const json_config1 = try std.fmt.allocPrint(allocator, "{s}", .{valid_json1});
    defer allocator.free(json_config1);

    const config1 = try Config.init(json_config1[0..], allocator, null, 1, true);
    try manager.pushNewConfig(config1);

    // New configuration to push
    const valid_json2 = "{\"root\": \"127.0.0.1:8081\"," ++ "\"routes\": {" ++ "\"*\": {\"backends\": [{\"host\": \"127.0.0.1:8081\",\"max_failure\": 5}]}," ++ "\"/\": {\"backends\": [" ++ "{\"host\": \"127.0.0.1:8082\",\"max_failure\": 2}," ++ "{\"host\": \"127.0.0.1:8083\",\"max_failure\": 10}]}" ++ "}}";
    const json_config2 = try std.fmt.allocPrint(allocator, "{s}", .{valid_json2});
    defer allocator.free(json_config2);

    const config2 = try Config.init(json_config2[0..], allocator, null, 2, true);
    // Shared atomic boolean for error detection
    var error_flag = Atomic(bool).init(false);

    // Spawn multiple threads for reading
    const reader_count: usize = 10;
    const iterations: usize = 1_000;
    var readers: [reader_count]std.Thread = undefined;
    for (0..reader_count) |i| {
        readers[i] = try std.Thread.spawn(
            .{ .allocator = allocator },
            getConfigH,
            .{ &manager, &error_flag, iterations },
        );
    }

    // Spawn one thread for pushing a new configuration
    var push_thread = try std.Thread.spawn(
        .{ .allocator = allocator },
        pushConfig,
        .{ &manager, config2 },
    );

    // Wait for all threads to finish
    for (0..reader_count) |i| {
        readers[i].join();
    }
    push_thread.join();

    // Verify no errors occurred
    try std.testing.expect(!error_flag.load(.acquire));
}

// Thread function for repeatedly getting the configuration
fn getConfigH(manager: *ConfigManager, error_flag: *Atomic(bool), iterations: usize) void {
    for (0..iterations) |_| {
        const current_config = manager.getCurrentConfig();
        if (!std.mem.eql(u8, current_config.conf.root, "127.0.0.1:8080") and
            !std.mem.eql(u8, current_config.conf.root, "127.0.0.1:8081"))
        {
            error_flag.store(true, .release);
            return;
        }
    }
}

fn getConfig(manager: *ConfigManager, result: *Atomic(bool)) void {
    const current_config = manager.getCurrentConfig();
    if (std.mem.eql(u8, current_config.conf.root, "127.0.0.1:8081")) {
        result.store(true, .release);
    }
}

fn pushConfig(manager: *ConfigManager, config: Config) void {
    manager.pushNewConfig(config) catch unreachable;
}
