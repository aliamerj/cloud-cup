const std = @import("std");
const Config = @import("config/config.zig").Config;
const Server = @import("server.zig").Server;

const c = @cImport({
    @cInclude("openssl/ssl.h");
    @cInclude("openssl/err.h");
});

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize OpenSSL's error strings and algorithms
    c.SSL_load_error_strings();
    _ = c.SSL_library_init();
    c.OPENSSL_add_all_algorithms_conf();

    // Create an SSL context
    const ctx = c.SSL_CTX_new(c.TLS_method());
    if (ctx == null) {
        std.debug.print("Failed to create SSL context\n", .{});
        return;
    }
    std.debug.print("SSL context created: {any}\n", .{ctx});

    // Clean up the SSL context at the end
    defer c.SSL_CTX_free(ctx);

    const parsed_config = Config.readConfigFile("config/main_config.json", allocator) catch |err| {
        std.log.err("Failed to load configuration file 'config/main_config.json': {any}", .{err});
        return;
    };

    var conf = Config.init(parsed_config, allocator);
    defer conf.deinit();

    const err = try conf.applyConfig();
    if (err != null) {
        std.log.err("{s}\n", .{err.?.err_message});
        return;
    }

    try Server.run(conf);
}
