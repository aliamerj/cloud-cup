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
    return ctx;
}

pub fn deinit(ssl_ctx: ?*c.SSL_CTX) void {
    c.SSL_CTX_free(ssl_ctx);
}

fn newSSLConnection(ssl_ctx: ?*c.SSL_CTX) !?*c.SSL {
    const ssl = c.SSL_new(ssl_ctx);
    if (ssl == null) {
        return error.FailedToCreateSSLObject;
    }
    return ssl;
}

pub fn acceptSSLConnection(ssl_ctx: ?*SSL_CTX, client_fd: std.posix.fd_t) !?*c.SSL {
    const ssl_client = try newSSLConnection(ssl_ctx);
    _ = c.SSL_set_fd(ssl_client, client_fd);

    const err = c.SSL_accept(ssl_client);

    if (err <= 0) {
        shutdown(ssl_client);
        closeConnection(ssl_client);
        return error.SSLHandshakeFailed;
    }
    return ssl_client;
}

pub fn readSSLRequest(ssl: ?*c.SSL, request_buffer: []u8) ![]u8 {
    const len = c.SSL_read(ssl, request_buffer.ptr, @intCast(request_buffer.len));
    if (len <= 0) {
        std.debug.print("SSL read failed\n", .{});
        return error.SSLWriteFailed;
    }
    return request_buffer[0..@intCast(len)];
}

pub fn writeSSLResponse(ssl: ?*c.SSL, response_buffer: []const u8, response_len: usize) !void {
    var total_written: usize = 0;
    while (total_written < response_len) {
        const written = c.SSL_write(ssl, response_buffer.ptr + total_written, @intCast(response_len - total_written));
        if (written <= 0) {
            const ssl_err = c.SSL_get_error(ssl, written);
            if (ssl_err == c.SSL_ERROR_WANT_WRITE or ssl_err == c.SSL_ERROR_WANT_READ) {
                continue; // Retry the write
            } else {
                std.debug.print("SSL write failed with error: {}\n", .{ssl_err});

                return error.SSLWriteFailed;
            }
        }
        total_written += @intCast(written);
    }
}

pub fn closeConnection(ssl: ?*c.SSL) void {
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
