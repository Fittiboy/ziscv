const std = @import("std");
const native_os = @import("builtin").os.tag;

pub fn openInputFile(init: std.process.Init, io: std.Io, gpa: std.mem.Allocator) std.Io.File {
    var args_iter = switch (native_os) {
        .wasi, .windows => try init.minimal.args.iterateAllocator(gpa),
        else => init.minimal.args.iterate(),
    };
    defer args_iter.deinit();
    _ = args_iter.skip();
    const filename = args_iter.next() orelse {
        std.process.fatal("No input file provided", .{});
    };
    const cwd = std.Io.Dir.cwd();

    const file = cwd.openFile(io, filename, .{ .allow_directory = false }) catch |err| {
        std.process.fatal("when trying to open file \"{s}\": {s}", .{ filename, @errorName(err) });
    };

    return file;
}
