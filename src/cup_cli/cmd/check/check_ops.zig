const std = @import("std");
const Config = @import("config").Config;
const SharedConfig = @import("common").SharedConfig;
const Diagnostic = @import("diagnostic.zig").Diagnostic;

pub fn respondWithDiagnostics(
    client_conn: std.net.Server.Connection,
    shm: SharedConfig,
    allocator: std.mem.Allocator,
) !void {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    try checkBackends(allocator, shm, &result, false);
    try client_conn.stream.writer().writeAll(result.items);
}

pub fn checkBackends(allocator: std.mem.Allocator, shm: SharedConfig, result: *std.ArrayList(u8), testing: bool) !void {
    var diagnostics = std.ArrayList(Diagnostic).init(allocator);
    defer diagnostics.deinit();

    const file_data = shm.readData();
    var parts = std.mem.split(u8, file_data[0..], "|");
    _ = parts.next();
    const json = std.mem.trimRight(u8, parts.next().?, &[_]u8{ 0, '\n', '\r', ' ', '\t' });

    var buffer: [4096]u8 = undefined;
    std.mem.copyForwards(u8, &buffer, json);
    var config = try Config.init(
        buffer[0..json.len],
        allocator,
        null,
        1,
        testing,
    );
    defer config.deinit();

    try gatherDiagnostics(&config, &diagnostics);

    try std.json.stringify(diagnostics.items, .{}, result.writer());
}

fn gatherDiagnostics(config: *Config, diagnostics: *std.ArrayList(Diagnostic)) !void {
    var routes = config.conf.routes.iterator();
    while (routes.next()) |kv| {
        for (kv.value_ptr.backends) |backend| {
            const diagnostic = Diagnostic.checkBackend(backend.host, kv.key_ptr.*);
            try diagnostics.append(diagnostic);
        }
    }
}

test "check backend - all backends unhealthy" {
    const allocator = std.testing.allocator;
    var buf: [4096]u8 = undefined;
    @memset(&buf, 0);

    const valid_json = "1|{\"root\": \"127.0.0.1:8080\"," ++ "\"routes\": {" ++ "\"*\": {\"backends\": [{\"host\": \"127.0.0.1:8081\",\"max_failure\": 5}]}," ++ "\"/\": {\"backends\": [" ++ "{\"host\": \"127.0.0.1:8082\",\"max_failure\": 2}," ++ "{\"host\": \"127.0.0.1:8083\",\"max_failure\": 10}]}" ++ "}}";
    const json_len = valid_json.len;

    // Copy valid_json into the fixed-size array
    std.mem.copyForwards(u8, &buf, valid_json[0..json_len]);

    var mutx = std.Thread.Mutex{};

    // Pass the fixed-size array to `SharedConfig.init`
    const shm = try SharedConfig.init(buf, &mutx);
    defer shm.deinit();

    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    try checkBackends(allocator, shm, &result, true);
    const expected_result =
        "[{\"host\":\"127.0.0.1:8081\",\"route\":\"*\",\"is_healthy\":false,\"error_message\":\"Failed to connect to backend\",\"error_name\":\"ConnectionRefused\"}," ++
        "{\"host\":\"127.0.0.1:8082\",\"route\":\"/\",\"is_healthy\":false,\"error_message\":\"Failed to connect to backend\",\"error_name\":\"ConnectionRefused\"}," ++
        "{\"host\":\"127.0.0.1:8083\",\"route\":\"/\",\"is_healthy\":false,\"error_message\":\"Failed to connect to backend\",\"error_name\":\"ConnectionRefused\"}]";

    try std.testing.expectEqualStrings(expected_result, result.items);
}
