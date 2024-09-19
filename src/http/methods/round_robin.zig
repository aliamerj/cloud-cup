const std = @import("std");

const Server = @import("../http.zig").Server;
const EpollNonblock = @import("../utils/epoll_nonblock.zig").EpollNonblock;

const ServerData = struct {
    server: Server,
    attempts: u32,
};

pub const Hash_map = std.AutoHashMap(usize, ServerData);

pub const RoundRobin = struct {
    const max_attempts: u32 = 5;
    servers: Hash_map = undefined,

    pub fn init(self: *RoundRobin, servers: []Server) !void {
        self.servers = Hash_map.init(std.heap.page_allocator);
        for (servers, 0..) |value, i| {
            try self.servers.put(i, .{ .server = value, .attempts = 0 });
        }
    }

    pub fn deinit(self: *RoundRobin) void {
        self.servers.deinit();
    }

    pub fn handle(self: RoundRobin, tcp_server: *std.net.Server, epoll: *EpollNonblock) !void {
        var events: [100]std.os.linux.epoll_event = undefined;
        var server_key: usize = 0;
        const servers_number = self.servers.count();

        while (true) {
            const event_count = try epoll.wait(&events);

            for (events[0..event_count]) |ev| {
                if (ev.data.fd == tcp_server.stream.handle) {
                    // Accept incoming connections
                    while (true) {
                        const conn = tcp_server.accept() catch |err| {
                            if (err == error.WouldBlock) break;
                            return err;
                        };
                        try epoll.new(conn.stream);
                    }
                } else {
                    var servers_down: usize = 0;
                    const client_fd = ev.data.fd;
                    var buffer: [8192]u8 = undefined;
                    const request_len = std.os.linux.read(client_fd, &buffer, buffer.len);

                    while (servers_number > servers_down) {
                        if (self.servers.get(server_key)) |server_to_run| {
                            var current_server = server_to_run;
                            if (current_server.attempts >= max_attempts) {
                                servers_down += 1;
                            }
                            // Connect to the backend and forward the request

                            connectAndForwardRequest(current_server.server, &buffer[0..request_len], client_fd) catch {
                                current_server.attempts += 1;
                                try self.servers.put(server_key, current_server);
                                findNextServer(servers_number, &server_key, current_server);
                                continue;
                            };

                            if (current_server.attempts > 0) {
                                current_server.attempts = 0;
                                try self.servers.put(server_key, current_server);
                            }
                            findNextServer(servers_number, &server_key, current_server);
                            break;
                        }
                    }
                    try self.sendBadGateway(ev.data.fd);
                }
            }
        }
    }

    fn findNextServer(servers_number: usize, server_key: *usize, server_data: ServerData) void {
        // Skip the current server if its attempts have reached the max
        if (server_data.attempts >= max_attempts) {
            server_key.* = (server_key.* + 1) % servers_number;
            return;
        }

        // Move to the next server, wrapping around if necessary
        server_key.* = (server_key.* + 1) % servers_number;
    }

    fn sendBadGateway(self: *RoundRobin, client_fd: i32) !void {
        _ = self;
        const response = "HTTP/1.1 502 Bad Gateway\r\nContent-Type: text/plain\r\nContent-Length: 16\r\n\r\n502 Bad Gateway\n";
        try std.posix.write(client_fd, response, response.len);
    }

    fn connectAndForwardRequest(server: Server, request: *const []u8, client_fd: i32) !void {
        const socket = try createSocket(server.host, server.port);

        try sendRequest(socket, request);
        try forwardResponse(socket, client_fd);
    }

    fn createSocket(host: []const u8, port: u16) !i32 {
        // todo fix this ??

        const addr = try std.net.Address.resolveIp(host, port);
        const sock = try std.posix.socket(std.posix.AF.INET, std.posix.SOCK.STREAM, std.posix.IPPROTO.TCP);
        const size = addr.getOsSockLen();
        const InProgress = std.posix.ConnectError.WouldBlock;
        var flags = try std.posix.fcntl(sock, std.posix.F.GETFL, 0);
        flags |= std.posix.O.NONBLOCK;
        _ = try std.posix.fcntl(sock, std.posix.F.SETFL, flags);
        std.posix.connect(sock, &addr.any, size) catch |err| {
            switch (err) {
                InProgress => std.debug.print("ok\n", .{}),
                else => return err,
            }
        };
        return sock;
    }

    fn sendRequest(socket_fd: i32, request: []const u8) !void {
        // todo fix this
        var total_sent: usize = 0;

        while (total_sent < request.len) {
            const bytes_sent = std.os.linux.write(socket_fd, request[total_sent..]);
            if (bytes_sent < 0) {
                const errno = std.os.errno();
                if (errno == std.os.linux.E.AGAIN or errno == std.os.linux.E.WOULDBLOCK) {
                    // If we can't send yet, wait for the socket to become writable using epoll
                    continue;
                } else {
                    return error.WriteFailed;
                }
            }
            total_sent += bytes_sent;
        }
    }

    fn forwardResponse(socket_fd: i32, client_fd: i32) !void {
        // fix this
        var response_buffer: [8192]u8 = undefined;

        while (true) {
            const response_len = std.os.linux.read(socket_fd, &response_buffer, response_buffer.len);
            if (response_len == 0) break; // End of response from server
            if (response_len < 0) {
                const errno = std.os.errno();
                if (errno == std.os.linux.E.AGAIN or errno == std.os.linux.E.WOULDBLOCK) {
                    // If the socket isn't ready to read, wait for it to become readable using epoll
                    continue;
                } else {
                    return error.ReadFailed;
                }
            }

            // Write the response back to the client
            var total_sent = 0;
            while (total_sent < response_len) {
                const bytes_sent = std.os.linux.write(client_fd, response_buffer[total_sent..response_len]);
                if (bytes_sent < 0) {
                    const errno = std.os.errno();
                    if (errno == std.os.linux.E.AGAIN or errno == std.os.linux.E.WOULDBLOCK) {
                        // If the client isn't ready to receive data, wait for it to become writable using epoll
                        continue;
                    } else {
                        return error.WriteFailed;
                    }
                }
                total_sent += bytes_sent;
            }
        }
    }

    fn setNonblockFd(fd: i32) !void {
        var flags = try std.posix.fcntl(fd, std.posix.F.GETFL, 0);
        var flags_s: *std.posix.O = @ptrCast(&flags);
        flags_s.NONBLOCK = true;
        _ = try std.posix.fcntl(fd, std.posix.F.SETFL, flags);
    }
};
