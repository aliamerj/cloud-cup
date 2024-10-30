const std = @import("std");
const SSL = @import("../../ssl/SSL.zig").SSL;

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
