const std = @import("std");

pub fn SharedMemory(comptime T: type) type {
    return struct {
        shared_memory: []align(4096) u8,
        mutx: ?*std.Thread.Mutex,

        pub fn init(raw_data: T, mutx: ?*std.Thread.Mutex) !SharedMemory(T) {
            const memory = try std.posix.mmap(
                null,
                4096,
                std.posix.PROT.READ | std.posix.PROT.WRITE,
                .{ .TYPE = .SHARED, .ANONYMOUS = true },
                -1,
                0,
            );

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
            self.mutx.?.lock();
            defer self.mutx.?.unlock();
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

test "test SharedMemory initialization and deinitialization" {
    const TestType = u32;
    const init_value: TestType = 42;

    var shared_mem = try SharedMemory(TestType).init(init_value, null);
    defer shared_mem.deinit();

    // Test if the shared memory is initialized with the correct value
    try std.testing.expectEqual(shared_mem.readData(), init_value);
}

test "test SharedMemory read and write" {
    const TestType = u32;
    const init_value: TestType = 0;
    const write_value: TestType = 1234;

    var shared_mem = try SharedMemory(TestType).init(init_value, null);
    defer shared_mem.deinit();

    // Test writing a new value to the shared memory
    const mem_ptr: *TestType = @ptrCast(shared_mem.shared_memory);
    mem_ptr.* = write_value;

    // Test reading the updated value from the shared memory
    try std.testing.expectEqual(shared_mem.readData(), write_value);
}

test "test SharedMemory writeStringData" {
    const allocator = std.testing.allocator;
    const TestType = [4096]u8;
    const init_value: TestType = [_]u8{0} ** 4096;
    const string_buf = try std.fmt.allocPrint(allocator, "Hello, shared memory!", .{});
    defer allocator.free(string_buf);
    var mutex = std.Thread.Mutex{};

    var shared_mem = try SharedMemory(TestType).init(init_value, &mutex);
    defer shared_mem.deinit();

    // Write a string to the shared memory
    shared_mem.writeStringData(string_buf);

    // Verify the string was written correctly
    const mem_ptr = shared_mem.shared_memory;

    try std.testing.expectEqual(0, std.mem.indexOf(u8, mem_ptr[0..], string_buf[0..]));
    try std.testing.expectEqual(0, std.mem.indexOf(u8, shared_mem.readData()[0..], string_buf[0..]));

    // Check null-termination
    try std.testing.expect(mem_ptr[string_buf.len] == 0);
}
