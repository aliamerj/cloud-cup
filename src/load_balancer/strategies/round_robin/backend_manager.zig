const std = @import("std");
const Backend_info = @import("../../route.zig").Backend;

const Backend_Data = struct {
    server: Backend_info,
    attempts: u32,
};

pub const Backend_Manager = struct {
    pub const Backend = struct {
        data: Backend_Data,
        next: ?*Backend,
    };

    allocator: std.mem.Allocator,
    head: ?*Backend,
    len: usize = 0,

    pub fn init(allocator: std.mem.Allocator) Backend_Manager {
        return Backend_Manager{
            .allocator = allocator,
            .head = null,
        };
    }

    pub fn deinit(self: *Backend_Manager) void {
        if (self.head) |head| {
            // Traverse until we loop back to the head
            var next = head.next;
            while (next != head) : (next = next.?.next) {
                self.allocator.destroy(next.?);
            }
            // Finally destroy the head node
            self.allocator.destroy(head);
        }

        self.head = null;
    }

    pub fn push(self: *Backend_Manager, backend_data: Backend_Data) !void {
        const new_node = try self.allocator.create(Backend);
        new_node.* = .{ .data = backend_data, .next = null };

        if (self.head == null) {
            // First node points to itself
            new_node.next = new_node;
            self.head = new_node;
        } else {
            // Insert new node at the end of the list, linking it back to head
            var current = self.head;
            while (current.?.next != self.head) {
                current = current.?.next;
            }

            // Link the new node in the circular list
            current.?.next = new_node;
            new_node.next = self.head;
        }
        self.len += 1;
    }
};
