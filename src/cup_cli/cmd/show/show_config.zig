const std = @import("std");
const SharedConfig = @import("common").SharedConfig;

pub fn respondWithConfig(client_conn: std.net.Server.Connection, shm: SharedConfig) !void {
    const json = showConfig(shm);
    try client_conn.stream.writer().writeAll(json);
}

fn showConfig(shm: SharedConfig) []const u8 {
    const shared_config = shm.readData();
    var parts = std.mem.split(u8, shared_config[0..], "|");
    _ = parts.next();
    return std.mem.trimRight(u8, parts.next().?, &[_]u8{ 0, '\n', '\r', ' ', '\t' });
}

test "showConfig" {
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

    const json = showConfig(shm);
    const expected_result = "{\"root\": \"127.0.0.1:8080\"," ++ "\"routes\": {" ++ "\"*\": {\"backends\": [{\"host\": \"127.0.0.1:8081\",\"max_failure\": 5}]}," ++ "\"/\": {\"backends\": [" ++ "{\"host\": \"127.0.0.1:8082\",\"max_failure\": 2}," ++ "{\"host\": \"127.0.0.1:8083\",\"max_failure\": 10}]}" ++ "}}";

    try std.testing.expectEqualStrings(expected_result, json);
}
