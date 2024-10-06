const std = @import("std");
const Epoll = @import("../http/epoll_handler.zig").Epoll;

const poxis = std.posix;

pub fn acceptIncomingConnections(tcp_server: *std.net.Server, epoll: Epoll) !void {
    while (true) {
        const conn = tcp_server.accept() catch |err| {
            if (err == error.WouldBlock) break; // No more connections to accept
            return err;
        };
        try epoll.new(conn.stream.handle);
    }
}

pub fn connectToBackend(address: std.net.Address) poxis.fd_t {
    const stream = std.net.tcpConnectToAddress(address) catch return -1;
    return stream.handle;
}

pub fn readClientRequest(client_fd: poxis.fd_t, buffer: []u8) ![]u8 {
    const bytes_read = try std.posix.recv(client_fd, buffer, 0);
    if (bytes_read <= 0) {
        return error.EmptyRequest;
    }

    return buffer[0..bytes_read];
}
pub fn forwardRequestToBackend(backend_fd: poxis.fd_t, request: []u8) !void {
    _ = try poxis.send(backend_fd, request, 0);
}

pub fn forwardResponseToClient(backend_fd: poxis.fd_t, client_fd: poxis.fd_t, response_buffer: []u8) !void {
    while (true) {
        const response_len = try poxis.read(backend_fd, response_buffer);
        if (response_len == 0) break; // EOF reached

        _ = poxis.send(client_fd, response_buffer[0..response_len], 0) catch |err| {
            if (err == error.BrokenPipe) {
                std.log.warn("BrokenPipe occur \n", .{});
                return;
            }
            return err;
        };
    }
    _ = std.posix.close(backend_fd);
}

pub fn closeConnection(epoll_fd: i32, client_fd: std.posix.fd_t) !void {
    try std.posix.epoll_ctl(epoll_fd, std.os.linux.EPOLL.CTL_DEL, client_fd, null);
    _ = std.posix.close(client_fd);
}

pub fn sendBadGateway(client_fd: i32) !void {
    const response = "HTTP/1.1 502 Bad Gateway\r\nContent-Type: text/plain\r\nContent-Length: 16\r\n\r\n502 Bad Gateway\n";
    _ = std.posix.send(client_fd, response, 0) catch |err| {
        if (err == error.BrokenPipe) {
            std.log.warn("BrokenPipe occur \n", .{});
            return;
        }
        return err;
    };
}
