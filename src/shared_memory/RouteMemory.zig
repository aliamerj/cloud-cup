const std = @import("std");

const O_CREAT = 0o100; // 64 in decimal
const O_RDWR = 0o2; // 2 in decimal
const O_TRUNC = 0o1000; // Or const O_TRUNC = 512;

pub fn createRouteMemory(
    shm_name: []const u8,
    version: usize,
) !void {
    var allocator = std.heap.page_allocator;
    const name_64 = std.hash.Fnv1a_64.hash(shm_name);
    var route_name: [:0]u8 = undefined;
    if (version == 1) {
        route_name = try std.fmt.allocPrintZ(allocator, "/{d}", .{name_64});
    } else {
        route_name = try std.fmt.allocPrintZ(allocator, "/{d}-{d}", .{ name_64, version });
    }
    defer allocator.free(route_name);

    const fd = std.c.shm_open(route_name, O_CREAT | O_RDWR | O_TRUNC, 0o666);
    if (fd == -1) {
        return error.OpenFailed;
    }
    defer _ = std.c.close(fd);

    // Set the size of the shared memory
    if (std.c.ftruncate(fd, 4096) != 0) {
        return error.ResizeFailed;
    }

    const memory = try std.posix.mmap(
        null,
        4096,
        std.posix.PROT.READ | std.posix.PROT.WRITE,
        .{ .TYPE = .SHARED },
        fd,
        0,
    );
    defer std.posix.munmap(memory);

    const data: *usize = @ptrCast(memory);
    data.* = 0;
}

pub const MemoryRoute = struct {
    fd: c_int,
    memory: []align(4096) u8,
    pub fn read(shm_name: []const u8, version: usize) !MemoryRoute {
        var allocator = std.heap.page_allocator;
        const name_64 = std.hash.Fnv1a_64.hash(shm_name);

        var route_name: [:0]u8 = undefined;
        if (version == 1) {
            route_name = try std.fmt.allocPrintZ(allocator, "/{d}", .{name_64});
        } else {
            route_name = try std.fmt.allocPrintZ(allocator, "/{d}-{d}", .{ name_64, version });
        }
        defer allocator.free(route_name);
        const fd = std.c.shm_open(route_name, O_RDWR, 0o666);
        if (fd == -1) {
            return error.ReadFailed;
        }

        const memory = try std.posix.mmap(
            null,
            4096,
            std.posix.PROT.READ | std.posix.PROT.WRITE,
            .{ .TYPE = .SHARED },
            fd,
            0,
        );

        const data: *usize = @ptrCast(memory);
        data.* = 0;

        return MemoryRoute{
            .fd = fd,
            .memory = memory,
        };
    }

    pub fn close(self: MemoryRoute) void {
        _ = std.c.close(self.fd);
        std.posix.munmap(self.memory);
    }
    pub fn write(self: MemoryRoute, raw_data: usize) void {
        const data: *usize = @ptrCast(self.memory);
        data.* = raw_data;
    }
};

pub fn deleteMemoryRoute(shm_name: []const u8, version: usize) !void {
    var allocator = std.heap.page_allocator;
    const name_64 = std.hash.Fnv1a_64.hash(shm_name);
    // Duplicate the slice as a null-terminated string.
    var route_name: [:0]u8 = undefined;
    if (version == 1) {
        route_name = try std.fmt.allocPrintZ(allocator, "/{d}", .{name_64});
    } else {
        route_name = try std.fmt.allocPrintZ(allocator, "/{d}-{d}", .{ name_64, version });
    }

    defer allocator.free(route_name);

    if (std.c.shm_unlink(route_name) != 0) {
        return error.DeleteMemoryRouteError;
    }
}
