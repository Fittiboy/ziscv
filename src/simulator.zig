const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var args_iter = init.minimal.args.iterate();
    _ = args_iter.skip();
    const filename = args_iter.next() orelse {
        std.process.fatal("No input file provided", .{});
    };
    const cwd = std.Io.Dir.cwd();

    const file = cwd.openFile(io, filename, .{ .allow_directory = false }) catch |err| {
        std.process.fatal("when trying to open file \"{s}\": {s}", .{ filename, @errorName(err) });
    };
    defer file.close(io);

    var reader_buf: [1024]u8 = undefined;
    var file_reader = file.reader(io, &reader_buf);
    const reader: *std.Io.Reader = &file_reader.interface;

    var stdout_buf: [1024]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), io, &stdout_buf);
    const stdout: *std.Io.Writer = &stdout_writer.interface;

    var machine: Machine = try .init(reader);

    try machine.simulate();
    const memory: *[32 * 4 * 1024 * 4]u8 = @ptrCast(&machine.memory);

    try stdout.writeAll(memory);
    try stdout.flush();
}

pub const Machine = struct {
    const Self = @This();

    prog_len: usize = 0,
    pc: u32 = 0x00000000,
    register_bank: [32]u32 = @splat(0x00000000),
    memory: [32 * 4 * 1024]u32 = undefined,

    const fresh: Self = .{};

    pub fn init(prog_reader: *std.Io.Reader) !Self {
        var machine: Self = .fresh;
        const memory: *[32 * 4 * 1024 * 4]u8 = @ptrCast(&machine.memory);
        var mem_writer: std.Io.Writer = .fixed(memory);
        machine.prog_len = try prog_reader.streamRemaining(&mem_writer);

        return machine;
    }

    pub fn simulate(self: *Self) !void {
        _ = self;
    }
};
