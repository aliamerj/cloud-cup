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
