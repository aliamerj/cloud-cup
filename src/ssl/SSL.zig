const std = @import("std");

const c = @cImport({
    @cInclude("openssl/ssl.h");
    @cInclude("openssl/err.h");
    @cInclude("openssl/bio.h");
    @cInclude("openssl/x509.h");
    @cInclude("openssl/rand.h");
    @cInclude("openssl/evp.h");
    @cInclude("openssl/pem.h");
});

pub const SSL_CTX = c.SSL_CTX;
pub const SSL = c.SSL;

pub fn initializeSSLContext(certFile: []const u8, keyFile: []const u8) !?*c.SSL_CTX {
    const err = c.SSL_library_init();

    if (err != 1) {
        std.log.err("error ssl start ", .{});
        return error.FailedToStartLibrary;
    }
    c.SSL_load_error_strings();
    _ = c.OpenSSL_add_ssl_algorithms();

    const method = c.TLS_server_method();
    const ctx = c.SSL_CTX_new(method);
    if (ctx == null) {
        std.debug.print("Failed to create SSL context\n", .{});
        return error.FailedToCreateContext;
    }

    var certFile_path: [4096]u8 = undefined;
    var keyFile_path: [4096]u8 = undefined;

    _ = try std.fs.realpath(certFile, &certFile_path);
    _ = try std.fs.realpath(keyFile, &keyFile_path);

    if (c.SSL_CTX_use_certificate_file(ctx, &certFile_path, c.SSL_FILETYPE_PEM) <= 0) {
        std.debug.print("Failed to load server certificate\n", .{});
        deinit(ctx);
        return error.FailedToLoadCertificate;
    }

    if (c.SSL_CTX_use_PrivateKey_file(ctx, &keyFile_path, c.SSL_FILETYPE_PEM) <= 0) {
        std.debug.print("Failed to load private key\n", .{});
        deinit(ctx);
        return error.FailedToLoadPrivateKey;
    }

    if (c.SSL_CTX_load_verify_locations(ctx, &certFile_path, null) <= 0) {
        std.debug.print("Failed to verify certification location \n", .{});
        deinit(ctx);
        return error.FailedToVerifyCertification;
    }
    c.SSL_CTX_set_verify(ctx, c.SSL_VERIFY_PEER, null);
    c.SSL_CTX_set_verify_depth(ctx, 1);

    // Enable session cache for session resumption
    const session_cache_mode = c.SSL_SESS_CACHE_SERVER;
    _ = c.SSL_CTX_set_session_cache_mode(ctx, session_cache_mode);
    _ = c.SSL_CTX_set_timeout(ctx, 300); // Set session timeout (5 min)

    // Enable session tickets for faster reconnections
    _ = c.SSL_CTX_set_options(ctx, c.SSL_OP_NO_TICKET);
    _ = c.SSL_CTX_set_session_id_context(ctx, @ptrCast(&session_cache_mode), session_cache_mode);

    return ctx;
}

pub fn deinit(ssl_ctx: ?*c.SSL_CTX) void {
    c.SSL_CTX_free(ssl_ctx);
}

pub fn acceptSSLConnection(ssl_ctx: ?*SSL_CTX, client_fd: std.posix.fd_t) !?*c.SSL {
    const ssl_client = c.SSL_new(ssl_ctx);
    if (ssl_client == null) {
        return error.FailedToCreateSSLObject;
    }

    _ = c.SSL_set_fd(ssl_client, client_fd);
    // Enable non-blocking I/O
    _ = c.SSL_set_mode(ssl_client, c.SSL_MODE_ACCEPT_MOVING_WRITE_BUFFER | c.SSL_MODE_ENABLE_PARTIAL_WRITE);

    const err = c.SSL_accept(ssl_client);

    if (err <= 0) {
        shutdown(ssl_client);
        closeConnection(ssl_client);
        return error.SSLHandshakeFailed;
    }
    return ssl_client;
}

// Read data with non-blocking handling and retries
pub fn readSSLRequest(ssl: *c.SSL, buffer: []u8) ![]u8 {
    while (true) {
        const len = c.SSL_read(ssl, buffer.ptr, @intCast(buffer.len));
        if (len > 0) return buffer[0..@intCast(len)];

        const ssl_err = c.SSL_get_error(ssl, len);
        switch (ssl_err) {
            c.SSL_ERROR_WANT_READ, c.SSL_ERROR_WANT_WRITE => continue, // Retry on these errors
            else => return error.SSLReadFailed,
        }
    }
}

// Write data with retries, handling non-blocking I/O
pub fn writeSSLResponse(ssl: *c.SSL, data: []const u8, request_len: usize) !void {
    var written: usize = 0;
    while (written < request_len) {
        const len = c.SSL_write(ssl, data.ptr + written, @intCast(request_len - written));
        if (len > 0) {
            written += @intCast(len);
            continue;
        }

        const ssl_err = c.SSL_get_error(ssl, len);
        switch (ssl_err) {
            c.SSL_ERROR_WANT_WRITE, c.SSL_ERROR_WANT_READ => continue, // Retry on these errors
            else => return error.SSLWriteFailed,
        }
    }
}
pub fn closeConnection(ssl: ?*c.SSL) void {
    _ = c.SSL_shutdown(ssl);
    c.SSL_free(ssl);
}

pub fn shutdown(ssl: ?*c.SSL) void {
    _ = c.SSL_shutdown(ssl);
}

// pub fn printSSLErrorMessage() void {
//     const err = c.ERR_get_error();
//     const err_str = c.ERR_error_string(err, null);
//     if (err_str != null) {
//         const err_cstr: [*c]const u8 = @ptrCast(err_str); // Convert to C string
//         std.debug.print("SSL Error: {s}\n", .{err_cstr}); // Print the string
//     } else {
//         std.debug.print("Unknown SSL error.\n", .{});
//     }
// }
