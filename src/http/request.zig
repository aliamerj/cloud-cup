const std = @import("std");

const poxis = std.posix;

pub fn connectToBackend(host: []const u8, port: u16) poxis.fd_t {
    const address = std.net.Address.parseIp4(host, port) catch return -1;
    const stream = std.net.tcpConnectToAddress(address) catch return -1;
    return stream.handle;
}

pub fn readClientRequest(client_fd: poxis.fd_t, buffer: []u8) ![]u8 {
    const bytes_read = try std.posix.read(client_fd, buffer);
    if (bytes_read <= 0) {
        return error.EmptyRequest;
    }

    return buffer[0..bytes_read];
}
pub fn forwardRequestToBackend(backend_fd: poxis.fd_t, request: []u8) !void {
    _ = try poxis.write(backend_fd, request);
}

pub fn forwardResponseToClient(backend_fd: poxis.fd_t, client_fd: poxis.fd_t, response_buffer: []u8) !void {
    while (true) {
        const response_len = try poxis.read(backend_fd, response_buffer);
        if (response_len == 0) break; // EOF reached

        _ = try poxis.write(client_fd, response_buffer[0..response_len]);
    }
}

pub fn sendBadGateway(client_fd: i32) !void {
    const response = "HTTP/1.1 502 Bad Gateway\r\nContent-Type: text/plain\r\nContent-Length: 16\r\n\r\n502 Bad Gateway\n";
    _ = try std.posix.write(client_fd, response);
}
