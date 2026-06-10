const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const simulator = b.addExecutable(.{
        .name = "ziscv-simulator",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/simulator.zig"),
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

    b.installArtifact(simulator);
    b.installArtifact(assembler_exe);

    const old_zig = @hasField(std.Build, "args");

    const simulator_run_step = b.step("simulate", "Run the Simulator");
    const simulator_run = b.addRunArtifact(simulator);
    if (old_zig) simulator_run.addArgs(b.args orelse &.{}) else simulator_run.addPassthruArgs();
    simulator_run_step.dependOn(&simulator_run.step);

    const assembler_run_step = b.step("assemble", "Run the Assembler");
    const assembler_run = b.addRunArtifact(assembler_exe);
    if (old_zig) assembler_run.addArgs(b.args orelse &.{}) else assembler_run.addPassthruArgs();
    assembler_run_step.dependOn(&assembler_run.step);

    const simulator_test = b.addTest(.{
        .root_module = simulator.root_module,
        .name = "assembler_test",
        .use_llvm = true,
    });

    const assembler_test = b.addTest(.{
        .root_module = assembler_exe.root_module,
        .name = "assembler_test",
        .use_llvm = true,
    });

    const simulator_test_step = b.step("test-simulator", "Test the simulator");
    const simulator_test_run = b.addRunArtifact(simulator_test);
    simulator_test_step.dependOn(&simulator_test_run.step);

    const assembler_test_step = b.step("test-assembler", "Test the assembler");
    const assembler_test_run = b.addRunArtifact(assembler_test);
    assembler_test_step.dependOn(&assembler_test_run.step);

    const test_step = b.step("test", "Test both the assembler and the simulator");
    test_step.dependOn(&simulator_test_run.step);
    test_step.dependOn(&assembler_test_run.step);
}
