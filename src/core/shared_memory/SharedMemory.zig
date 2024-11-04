const std = @import("std");

pub fn SharedMemory(comptime T: type) type {
    return struct {
        shared_memory: []align(4096) u8,
        mutx: *std.Thread.Mutex,

        pub fn init(raw_data: T, mutx: *std.Thread.Mutex) !SharedMemory(T) {
            const memory = try std.posix.mmap(
                null,
                4096,
                std.posix.PROT.READ | std.posix.PROT.WRITE,
                .{ .TYPE = .SHARED, .ANONYMOUS = true },
                -1,
                0,
            );

            @memset(memory, 0x55);
            const data: *T = @ptrCast(memory);
            data.* = raw_data;

            return .{
                .shared_memory = memory,
                .mutx = mutx,
            };
        }
        pub fn deinit(self: SharedMemory(T)) void {
            std.posix.munmap(self.shared_memory);
        }

        pub fn readData(self: SharedMemory(T)) T {
            const data: *T = @ptrCast(self.shared_memory);
            return data.*;
        }

        pub fn writeStringData(self: SharedMemory(T), buf: []u8) void {
            self.mutx.lock();
            defer self.mutx.unlock();
            @memset(self.shared_memory[0..], 0x00);
            std.mem.copyForwards(u8, self.shared_memory[0..], buf);
            if (buf.len < self.shared_memory.len) {
                self.shared_memory[buf.len] = 0;
            }

            std.posix.msync(self.shared_memory[0..], std.posix.MSF.SYNC) catch |e| {
                std.log.err("{any}", .{e});
                return;
            };
        }
    };
}
