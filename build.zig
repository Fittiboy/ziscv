const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .name = "ziscv",
        .root_module = lib_mod,
    });

    b.installArtifact(lib);

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "ziscv",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the executable");
    const run = b.addRunArtifact(exe);
    run_step.dependOn(&run.step);

    const lib_test = b.addTest(.{
        .root_module = lib_mod,
        .name = "lib_test",
        .use_llvm = true,
    });

    const lib_test_step = b.step("test-lib", "Test the library");
    const lib_test_run = b.addRunArtifact(lib_test);
    lib_test_step.dependOn(&lib_test_run.step);

    const exe_test = b.addTest(.{
        .root_module = exe_mod,
        .name = "exe_test",
        .use_llvm = true,
    });

    const exe_test_step = b.step("test-exe", "Test the exerary");
    const exe_test_run = b.addRunArtifact(exe_test);
    exe_test_step.dependOn(&exe_test_run.step);

    const test_step = b.step("test", "Test both the library and the executable");
    test_step.dependOn(&lib_test_run.step);
    test_step.dependOn(&exe_test_run.step);
}
