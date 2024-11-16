const std = @import("std");
const ssl_struct = @import("../ssl/SSL.zig");
const Config = @import("config.zig").Config;

const Atomic = std.atomic.Value;

pub const Config_Manager = struct {
    const Node = struct {
        data: Config,
    };

    allocator: std.mem.Allocator,
    head: Atomic(?*Node),

    pub fn init(allocator: std.mem.Allocator) Config_Manager {
        return Config_Manager{
            .allocator = allocator,
            .head = Atomic(?*Node).init(null),
        };
    }
    pub fn deinit(self: *Config_Manager) void {
        const head = self.head.load(.acquire) orelse unreachable;
        @constCast(&head.data).deinit();

        if (head.data.conf.ssl) |s| {
            ssl_struct.deinit(@constCast(s));
        }

        self.allocator.destroy(head);
    }

    pub fn pushNewConfig(self: *Config_Manager, config: Config) !void {
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
                    old_config.data.deinitMemory();
                    old_config.data.deinitBuilder();

                    if (old_config.data.conf.ssl) |s| {
                        ssl_struct.deinit(s);
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

    pub fn getCurrentConfig(self: *Config_Manager) Config {
        const head = self.head.load(.acquire) orelse unreachable;
        return head.data;
    }
};
