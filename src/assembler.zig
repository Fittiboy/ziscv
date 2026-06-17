const std = @import("std");
const file_helper = @import("file_helper.zig");
const resolver = @import("resolver.zig");
const encoder = @import("encoder.zig");

const Validator = @import("validator.zig");

const native_os = @import("builtin").os.tag;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    const program_file = try file_helper.openInputFile(init, io, gpa);
    defer program_file.close(io);
    var file_buffer: [1024]u8 = undefined;
    var file_reader: std.Io.File.Reader = .init(program_file, io, &file_buffer);
    const reader = &file_reader.interface;

    const prog_buf = try reader.allocRemaining(gpa, .unlimited);
    defer gpa.free(prog_buf);

    var validator: Validator = .init(prog_buf);
    defer validator.deinit(gpa);

    var validated: std.ArrayList(Validator.ValidatedUnit) = .empty;
    errdefer validated.deinit(gpa);

    while (try validator.next(gpa)) |unit| {
        try validated.append(gpa, unit);
    }

    const validated_buf = try validated.toOwnedSlice(gpa);
    defer gpa.free(validated_buf);

    const resolved = try resolver.resolveProgram(gpa, validated_buf);
    defer gpa.free(resolved);

    var stdout_buf: [1024]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), io, &stdout_buf);
    const stdout: *std.Io.Writer = &stdout_writer.interface;

    for (resolved) |instruction| {
        try writeInstruction(encoder.encodeInstruction(instruction), stdout);
    }

    try stdout.flush();
}

fn writeInstruction(instruction: encoder.MachineInstruction, writer: *std.Io.Writer) !void {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, instruction.raw, .little);
    try writer.writeAll(&bytes);
}
