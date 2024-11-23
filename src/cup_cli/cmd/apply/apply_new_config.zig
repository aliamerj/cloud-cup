const std = @import("std");
const configuration = @import("config");
const SharedConfig = @import("common").SharedConfig;
const Config = configuration.Config;

pub fn applyNewConfig(
    client_conn: std.net.Server.Connection,
    command: []u8,
    shm: SharedConfig,
    allocator: std.mem.Allocator,
) !void {
    const config_path = getFilepath(command) catch {
        try client_conn.stream.writer().writeAll("File path for new config required\n");
        return;
    };

    var buffer: [4096]u8 = undefined;
    const file_data = try loadConfigFile(config_path, &buffer);
    const current_config_version = try parseSharedConfigVersion(shm);

    try applyConfig(
        allocator,
        shm,
        current_config_version,
        buffer[0..file_data.len],
        client_conn.stream.writer(),
    );

    try client_conn.stream.writer().writeAll("New config applied successfully\n");
}

fn applyConfig(
    allocator: std.mem.Allocator,
    shm: SharedConfig,
    current_config_version: usize,
    new_config: []u8,
    writer: ?std.net.Stream.Writer,
) !void {
    var config = Config.init(
        new_config,
        allocator,
        writer,
        current_config_version + 1,
        true,
    ) catch {
        return;
    };
    defer {
        config.deinitBuilder();
        config.deinitStrategies();
        config.config_parsed.deinit();
    }

    try Config.share(shm, current_config_version + 1, new_config);
}
fn getFilepath(command: []u8) ![]const u8 {
    var parts = std.mem.split(u8, command, "|");
    _ = parts.next();
    const file_path = parts.next();

    if (file_path == null) {
        return error.FilePahtNotFound;
    }
    return std.mem.trim(u8, file_path.?, "\n");
}

fn loadConfigFile(file_path: []const u8, buffer: *[4096]u8) ![]const u8 {
    return std.fs.cwd().readFile(file_path, buffer) catch |err| {
        var error_message: [128]u8 = undefined;
        const message = try std.fmt.bufPrint(&error_message, "Failed to load config '{s}': {s}", .{ file_path, @errorName(err) });
        return error_message[0..message.len];
    };
}

fn parseSharedConfigVersion(shm: SharedConfig) !usize {
    const version_str = @constCast(&std.mem.split(u8, shm.readData()[0..], "|")).next().?;
    return std.fmt.parseInt(usize, version_str, 10);
}

test "applyNewConfig" {
    const allocator = std.testing.allocator;
    var buf: [4096]u8 = undefined;
    @memset(&buf, 0);

    const valid_json = "5|{\"root\": \"127.0.0.1:8080\"," ++ "\"routes\": {" ++ "\"*\": {\"backends\": [{\"host\": \"127.0.0.1:8081\",\"max_failure\": 5}]}," ++ "\"/\": {\"backends\": [" ++ "{\"host\": \"127.0.0.1:8082\",\"max_failure\": 2}," ++ "{\"host\": \"127.0.0.1:8083\",\"max_failure\": 10}]}" ++ "}}";
    const json_len = valid_json.len;

    // Copy valid_json into the fixed-size array
    std.mem.copyForwards(u8, &buf, valid_json[0..json_len]);

    var mutx = std.Thread.Mutex{};

    // Pass the fixed-size array to `SharedConfig.init`
    const shm = try SharedConfig.init(buf, &mutx);
    defer shm.deinit();

    const current_config_version = try parseSharedConfigVersion(shm);
    try std.testing.expect(current_config_version == 5);

    var new_buf: [4096]u8 = undefined;
    @memset(&new_buf, 0);

    const new_valid_json = "{\"root\": \"127.0.0.1:8085\"," ++ "\"routes\": {" ++ "\"*\": {\"backends\": [{\"host\": \"127.0.0.1:8081\",\"max_failure\": 5}]}," ++ "\"/\": {\"backends\": [" ++ "{\"host\": \"127.0.0.1:8082\",\"max_failure\": 2}," ++ "{\"host\": \"127.0.0.1:8083\",\"max_failure\": 10}]}" ++ "}}";
    const new_json_len = new_valid_json.len;

    // Copy valid_json into the fixed-size array
    std.mem.copyForwards(u8, &new_buf, new_valid_json[0..new_json_len]);

    try applyConfig(allocator, shm, current_config_version, new_buf[0..new_json_len], null);

    const expected_json = "6|{\"root\": \"127.0.0.1:8085\"," ++ "\"routes\": {" ++ "\"*\": {\"backends\": [{\"host\": \"127.0.0.1:8081\",\"max_failure\": 5}]}," ++ "\"/\": {\"backends\": [" ++ "{\"host\": \"127.0.0.1:8082\",\"max_failure\": 2}," ++ "{\"host\": \"127.0.0.1:8083\",\"max_failure\": 10}]}" ++ "}}";
    try std.testing.expectStringStartsWith(expected_json, shm.readData()[0..new_json_len]);
}
