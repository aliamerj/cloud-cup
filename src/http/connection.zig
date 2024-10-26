const std = @import("std");
const bssl = @cImport({
    @cInclude("openssl/ssl.h");
    @cInclude("openssl/err.h");
    @cInclude("openssl/bio.h");
    @cInclude("openssl/x509.h");
    @cInclude("openssl/rand.h");
    @cInclude("openssl/evp.h");
    @cInclude("openssl/pem.h");
});

pub const ConnectionData = struct {
    fd: i32 = undefined,
    ssl: ?*bssl.SSL = undefined,
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
