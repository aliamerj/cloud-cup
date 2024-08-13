const std = @import("std");

const Allocator = std.mem.Allocator;

const Options = struct {
    host: []const u8,
    port: usize,
};

pub const Config = struct {
    options: Options,
    allocator: Allocator,

    pub fn init(allocator: Allocator, json_file_path: []const u8) !Config {
        const data = try std.fs.cwd().readFileAlloc(allocator, json_file_path, 512);
        defer allocator.free(data);
        const parse = try std.json.parseFromSlice(Options, allocator, data, .{ .allocate = .alloc_always });
        defer parse.deinit();

        return Config{
            .allocator = allocator,
            .options = parse.value,
        };
    }

    pub fn run(self: *const Config) void {
        // todo:
        std.debug.print("Server running on {s}:{any}\n", .{ self.options.host, self.options.port });
    }
};
