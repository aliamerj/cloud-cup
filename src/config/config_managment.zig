const std = @import("std");
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
                    // Todo: free the old config
                    // current_head.data.deinit();
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
