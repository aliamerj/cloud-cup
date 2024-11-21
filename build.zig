const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSafe,
    });

    const core_md = b.createModule(.{
        .root_source_file = b.path("modules/core/core.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
    });
    // Add include path for BoringSSL headers
    core_md.addIncludePath(b.path("libs/boringssl/include"));

    // Add the BoringSSL libraries
    core_md.addCSourceFile(.{ .file = b.path("libs/boringssl/build/libdecrepit.a") });
    core_md.addCSourceFile(.{ .file = b.path("libs/boringssl/build/libcrypto.a") });
    core_md.addCSourceFile(.{ .file = b.path("libs/boringssl/build/libssl.a") });
    core_md.addCSourceFile(.{ .file = b.path("libs/boringssl/build/libpki.a") });

    const exe = b.addExecutable(.{
        .name = "cloud-cup",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    exe.root_module.addImport("core", core_md);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
