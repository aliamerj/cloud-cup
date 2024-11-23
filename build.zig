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

    const config_md = b.createModule(.{
        .root_source_file = b.path("modules/config/configuration.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lb_md = b.createModule(.{
        .root_source_file = b.path("modules/load_balancer/load_balancer.zig"),
        .target = target,
        .optimize = optimize,
    });

    const common_md = b.createModule(.{
        .root_source_file = b.path("modules/common/common.zig"),
        .target = target,
        .optimize = optimize,
    });

    config_md.addImport("core", core_md);
    config_md.addImport("common", common_md);
    config_md.addImport("loadBalancer", lb_md);

    lb_md.addImport("core", core_md);
    lb_md.addImport("common", common_md);

    const exe = b.addExecutable(.{
        .name = "cloud-cup",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    exe.root_module.addImport("core", core_md);
    exe.root_module.addImport("config", config_md);
    exe.root_module.addImport("loadBalancer", lb_md);
    exe.root_module.addImport("common", common_md);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const common_unit_tests = b.addTest(.{
        .root_source_file = b.path("modules/common/common.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const run_common_unit_tests = b.addRunArtifact(common_unit_tests);

    const config_unit_tests = b.addTest(.{
        .root_source_file = b.path("modules/config/configuration.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    config_unit_tests.root_module.addImport("core", core_md);
    config_unit_tests.root_module.addImport("common", common_md);
    config_unit_tests.root_module.addImport("loadBalancer", lb_md);
    const run_config_unit_tests = b.addRunArtifact(config_unit_tests);

    const core_unit_tests = b.addTest(.{
        .root_source_file = b.path("modules/core/core.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    // Add include path for BoringSSL headers
    core_unit_tests.addIncludePath(b.path("libs/boringssl/include"));

    // Add the BoringSSL libraries
    core_unit_tests.addCSourceFile(.{ .file = b.path("libs/boringssl/build/libdecrepit.a") });
    core_unit_tests.addCSourceFile(.{ .file = b.path("libs/boringssl/build/libcrypto.a") });
    core_unit_tests.addCSourceFile(.{ .file = b.path("libs/boringssl/build/libssl.a") });
    core_unit_tests.addCSourceFile(.{ .file = b.path("libs/boringssl/build/libpki.a") });
    const run_core_unit_tests = b.addRunArtifact(core_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_common_unit_tests.step);
    test_step.dependOn(&run_core_unit_tests.step);
    test_step.dependOn(&run_config_unit_tests.step);
}
