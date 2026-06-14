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
    if (old_zig) {
        simulator_run.addArgs(b.args orelse &.{});
    } else {
        simulator_run.addPassthruArgs();
    }
    simulator_run_step.dependOn(&simulator_run.step);

    const assembler_run_step = b.step("assemble", "Run the Assembler");
    const assembler_run = b.addRunArtifact(assembler_exe);
    if (old_zig) {
        assembler_run.addArgs(b.args orelse &.{});
    } else {
        assembler_run.addPassthruArgs();
    }
    assembler_run_step.dependOn(&assembler_run.step);

    const test_exe = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .name = "test",
        .use_llvm = true,
    });

    const test_step = b.step("test", "Test the application");
    const test_run = b.addRunArtifact(test_exe);
    test_step.dependOn(&test_run.step);
}
