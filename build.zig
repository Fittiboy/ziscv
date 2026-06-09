const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "ziscv",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const assembler_exe = b.addExecutable(.{
        .name = "ziscv-assembler",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/assembler.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    b.installArtifact(exe);
    b.installArtifact(assembler_exe);

    const run_step = b.step("run", "Run the Simulator");
    const run = b.addRunArtifact(exe);
    run.addPassthruArgs();
    run_step.dependOn(&run.step);

    const assembler_run_step = b.step("assemble", "Run the Assembler");
    const assembler_run = b.addRunArtifact(assembler_exe);
    assembler_run.addPassthruArgs();
    assembler_run_step.dependOn(&assembler_run.step);

    const exe_test = b.addTest(.{
        .root_module = exe.root_module,
        .name = "assembler_test",
        .use_llvm = true,
    });

    const assembler_test = b.addTest(.{
        .root_module = assembler_exe.root_module,
        .name = "assembler_test",
        .use_llvm = true,
    });

    const exe_test_step = b.step("test-simulator", "Test the simulator");
    const exe_test_run = b.addRunArtifact(exe_test);
    exe_test_step.dependOn(&exe_test_run.step);

    const assembler_test_step = b.step("test-assembler", "Test the assembler");
    const assembler_test_run = b.addRunArtifact(assembler_test);
    assembler_test_step.dependOn(&assembler_test_run.step);

    const test_step = b.step("test", "Test both the assembler and the simulator");
    test_step.dependOn(&exe_test_run.step);
    test_step.dependOn(&assembler_test_run.step);
}
