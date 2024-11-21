const std = @import("std");
const SSL = @import("SSL.zig").SSL;

pub const ConnectionData = struct {
    fd: i32 = undefined,
    ssl: ?*SSL = undefined,
};

const ConnectionPool = std.heap.MemoryPoolExtra(ConnectionData, .{ .growable = true });

pub const Connection = struct {
    pool: ConnectionPool,

    pub fn init(allocator: std.mem.Allocator) Connection {
        return Connection{ .pool = ConnectionPool.init(allocator) };
    }

    pub fn deinit(self: *Connection) void {
        self.pool.deinit();
    }

    pub fn create(self: *Connection, conn_data: ConnectionData) !*ConnectionData {
        const conn = try self.pool.create();
        conn.* = conn_data;
        return conn;
    }

    pub fn destroy(self: *Connection, conn: *ConnectionData) void {
        self.pool.destroy(conn);
    }
};

test "Connection test suite" {
    const allocator = std.testing.allocator;

    var connection = Connection.init(allocator);

    const conn_data = ConnectionData{ .fd = 42, .ssl = null };
    const conn_ptr = try connection.create(conn_data);

    try std.testing.expect(conn_ptr.*.fd == 42);
    try std.testing.expect(conn_ptr.*.ssl == null);

    connection.destroy(conn_ptr);

    const conn_ptr2 = try connection.create(ConnectionData{ .fd = 128, .ssl = null });
    try std.testing.expect(conn_ptr2.*.fd == 128);
    connection.destroy(conn_ptr2);

    connection.deinit();
}

test "stress test with multiple connections" {
    const allocator = std.testing.allocator;
    var connection = Connection.init(allocator);

    const max_connections = 100;
    var connections: [max_connections]*ConnectionData = undefined;

    // Create multiple connections
    for (connections, 0..max_connections) |_, i| {
        connections[i] = try connection.create(ConnectionData{ .fd = @intCast(i), .ssl = null });
        try std.testing.expect(connections[i].fd == i);
    }

    // Destroy all connections
    for (connections) |conn| {
        connection.destroy(conn);
    }

    connection.deinit();
}

test "double destroy edge case" {
    const allocator = std.testing.allocator;
    var connection = Connection.init(allocator);

    const conn = try connection.create(ConnectionData{ .fd = 10, .ssl = null });

    connection.destroy(conn);

    // Attempt to destroy the same connection again
    // This should be safe (noop or error, depending on your implementation)
    connection.destroy(conn);

    connection.deinit();
}

test "handle uninitialized connection data" {
    const allocator = std.testing.allocator;
    var connection = Connection.init(allocator);

    const conn_data: ConnectionData = undefined; // Uninitialized
    const conn_ptr = try connection.create(conn_data);

    // Expect default values due to initialization
    try std.testing.expect(conn_ptr.*.fd == 0); // Default value for i32
    try std.testing.expect(conn_ptr.*.ssl == null); // Default for ?*

    connection.destroy(conn_ptr);
    connection.deinit();
}
