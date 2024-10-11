const std = @import("std");
const Config = @import("../config/config.zig").Config;
const Route = @import("../load_balancer/route.zig").Route;

const Command = enum {
    ShowStatus,
    ShowConfig,
    Unknown,
};

pub fn processCLICommand(command: []u8, client_conn: std.net.Server.Connection, config: Config, allocator: std.mem.Allocator) !void {

    // Parse the command
    switch (parseCommand(command)) {
        .ShowStatus => {
            const response = "Cloud-Cup is running";
            _ = try client_conn.stream.writer().writeAll(response);
        },
        .ShowConfig => {
            const config_json = try convertToJSONConfig(config, allocator);
            defer config_json.deinit();
            _ = try client_conn.stream.writer().writeAll(config_json.items);
        },
        .Unknown => {
            const response = "Unknown command";
            _ = try client_conn.stream.writer().writeAll(response);
        },
    }
}

fn parseCommand(command: []const u8) Command {
    if (std.mem.eql(u8, command, "show-status\n")) return Command.ShowStatus;
    if (std.mem.eql(u8, command, "show-config\n")) return Command.ShowConfig;
    return Command.Unknown;
}

fn convertToJSONConfig(config: Config, allocator: std.mem.Allocator) !std.ArrayList(u8) {
    var strings = std.ArrayList(u8).init(allocator);
    errdefer strings.deinit();
    const writer = strings.writer();

    var x = std.json.writeStream(writer, .{});
    try x.beginObject();

    // Write the "root" field
    try x.objectField("root");
    _ = try x.write(config.root); // Use x.write instead of writer.write

    // Write the "routes" field
    try x.objectField("routes");
    try x.beginObject();

    // Iterate over the routes hash map and write each route
    var it = config.routes.iterator();
    while (it.next()) |kv| {
        const route_key = kv.key_ptr.*;
        const route_value = kv.value_ptr.*;

        // Write the route key
        try x.objectField(route_key);

        // Begin the route object
        try x.beginObject();

        // Write the "backends" field
        try x.objectField("backends");
        try x.beginArray();
        for (route_value.backends) |backend| {
            try x.beginObject();
            try x.objectField("host");
            try x.write(backend.host);
            try x.objectField("max_failure");
            try x.write(backend.max_failure);
            try x.endObject();
        }
        try x.endArray();

        // Write the "strategy" field if it exists
        try x.objectField("strategy");
        try x.write(route_value.strategy);

        // End the route object
        try x.endObject();
    }

    // End the "routes" object
    try x.endObject();

    // End the overall JSON object
    try x.endObject();

    return strings;
}
