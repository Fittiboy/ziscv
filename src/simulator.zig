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

    _ = try reader.streamRemaining(stdout);
    try stdout.flush();
}
