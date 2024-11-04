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
        const node = try self.allocator.create(Node);
        var head_ptr = self.head.load(.acquire);
        node.* = .{ .data = config };

        if (head_ptr) |current_head| {
            while (true) {
                const result = self.head.cmpxchgWeak(
                    current_head,
                    node,
                    .acquire,
                    .monotonic,
                );

                if (result != null) {
                    current_head.data.conf.strategy_hash.deinit();
                    current_head.data.deinitBuilder();

                    if (current_head.data.conf.ssl) |s| {
                        ssl_struct.deinit(@constCast(s));
                    }
                    current_head.data.config_parsed.deinit();
                    self.allocator.destroy(current_head);
                    break;
                }

                // Otherwise, reload the head_ptr and try again
                head_ptr = self.head.load(.acquire);
            }
            return;
        }

        self.head.store(node, .release);
    }

    pub fn getCurrentConfig(self: *Config_Manager) Config {
        const head = self.head.load(.acquire) orelse unreachable;
        return head.data;
    }
};
