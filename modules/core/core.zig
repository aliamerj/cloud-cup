pub const Epoll = @import("epoll_handler.zig").Epoll;
pub const SSL = @import("SSL.zig");
pub const conn = @import("connection.zig");
pub const server_ops = @import("server_ops.zig");

test "test all" {
    _ = @import("connection.zig");
    _ = @import("epoll_handler.zig");
    _ = @import("http_ops.zig");
}
