const std = @import("std");
const ziscv = @import("root.zig");

pub fn main(init: std.process.Init) !void {
    _ = init;
    std.debug.print("Hello, RISC-V!\n", .{});
    _ = try ziscv.assembler.parseInstruction("add x1, x2, x3");
}
