const std = @import("std");

pub fn build(b: *std.Build) void {
    var target_query = b.standardTargetOptionsQueryOnly(.{});
    const optimize = b.standardOptimizeOption(.{});
    const valgrind = b.option(bool, "valgrind", "Compile for Valgrind analysis") orelse false;

    if (valgrind) target_query.cpu_model = .baseline;
    const target = b.resolveTargetQuery(target_query);

    const simulator = b.addExecutable(.{
        .name = "ziscv-simulator",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/simulator.zig"),
            .target = target,
            .optimize = optimize,

            // Get some more helpful machinery for analysis
            .valgrind = if (valgrind) valgrind else null,
            .strip = if (valgrind) false else null,
            .omit_frame_pointer = if (valgrind) false else null,
        }),
        .use_llvm = if (valgrind) true else null,
    });

    const assembler = b.addExecutable(.{
        .name = "ziscv-assembler",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/assembler.zig"),
            .target = target,
            .optimize = optimize,

            // Get some more helpful machinery for analysis
            .valgrind = if (valgrind) valgrind else null,
            .strip = if (valgrind) false else null,
            .omit_frame_pointer = if (valgrind) false else null,
        }),
        .use_llvm = if (valgrind) true else null,
    });

    b.installArtifact(simulator);
    b.installArtifact(assembler);

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
    const assembler_run = b.addRunArtifact(assembler);
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
