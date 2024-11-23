pub const Route = @import("route.zig").Route;
pub const Config = @import("config.zig").Config;
pub const ConfigManager = @import("config_managment.zig").ConfigManager;

test "test all " {
    _ = @import("route.zig");
    _ = @import("config.zig");
    _ = @import("config_builder.zig");
    _ = @import("config_managment.zig");
}
