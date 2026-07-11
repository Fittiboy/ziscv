const std = @import("std");
const native_os = @import("builtin").os.tag;

const encoder = @import("encoder.zig");
const file_helper = @import("file_helper.zig");
const resolver = @import("resolver.zig");
const Validator = @import("validator.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena;

    const process_allocator = arena.allocator();

    const program_file = try file_helper.openInputFile(init, io, process_allocator);
    defer program_file.close(io);
    var file_buffer: [1024]u8 = undefined;
    var file_reader: std.Io.File.Reader = .init(program_file, io, &file_buffer);
    const reader = &file_reader.interface;

    const prog_buf = try reader.allocRemaining(process_allocator, .unlimited);

    var validator: Validator = .init(prog_buf);

    var validated: std.ArrayList(Validator.ValidatedUnit) = .empty;

    while (try validator.next(process_allocator)) |unit| {
        try validated.append(process_allocator, unit);
    }

    const resolved = try resolver.resolveProgram(process_allocator, validated.items);

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
