const std = @import("std");

pub fn parseServerAddress(input: []const u8) !std.net.Address {
    var split_iter = std.mem.splitSequence(u8, input, ":");
    const host = split_iter.next() orelse return error.InvalidHost;
    const port_str = split_iter.next() orelse null; // Use null if no port is specified

    var port: u16 = undefined;
    if (port_str != null) {
        port = try std.fmt.parseInt(u16, port_str.?, 10);
    } else {
        port = 80;
    }

    // Resolve the IP address or domain name
    const address_info = try std.net.Address.resolveIp(host, port);
    return address_info;
}

pub const ExtractedPath = struct {
    sub: bool,
    path: []const u8,
};

pub fn extractPath(request: []const u8) !ExtractedPath {
    const first_space_index = std.mem.indexOf(u8, request, " ") orelse return error.InvalidPath;
    const second_space_index = std.mem.indexOf(u8, request[first_space_index + 1 ..], " ") orelse return error.InvalidPath;

    var path = request[first_space_index + 1 .. first_space_index + 1 + second_space_index];

    if (std.mem.indexOf(u8, path, "?")) |query_index| {
        path = path[0..query_index];
    }

    if (path.len > 1 and std.mem.endsWith(u8, path, "/")) {
        path = path[0 .. path.len - 1];
    }

    const sub_route = std.mem.indexOf(u8, path, "/") != null and path.len > 1;

    return ExtractedPath{
        .sub = sub_route,
        .path = path,
    };
}

pub fn setNonblock(fd: std.posix.fd_t) !void {
    var flags = try std.posix.fcntl(fd, std.posix.F.GETFL, 0);
    var flags_s: *std.posix.O = @ptrCast(&flags);
    flags_s.NONBLOCK = true;
    _ = try std.posix.fcntl(fd, std.posix.F.SETFL, flags);
}
