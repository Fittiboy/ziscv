const std = @import("std");
const ArrayList = std.ArrayList;
const StringMap = std.StaticStringMap(u32);

pub const Program = ArrayList(Line);
pub const Line = struct {
    label_def: ?[]const u8,
    instruction: ?Instruction,
};
pub const Instruction = struct {
    mnemonic: []const u8,
    operands: ?[]Operand,
};
pub const Operand = union(enum) {
    register: u5,
    memory: Memory,
    immediate: Immediate,
    label_ref: []const u8,
};
pub const Memory = struct {
    immediate: Immediate,
    register: u5,
};
pub const Immediate = u32;

pub const reg_aliases: StringMap = .initComptime(.{
    .{ "zero", 0 }, .{ "ra", 1 },  .{ "sp", 2 },  .{ "gp", 3 },
    .{ "tp", 4 },   .{ "t0", 5 },  .{ "t1", 6 },  .{ "t2", 7 },
    .{ "s0", 8 },   .{ "fp", 8 },  .{ "s1", 9 },  .{ "a0", 10 },
    .{ "a1", 11 },  .{ "a2", 12 }, .{ "a3", 13 }, .{ "a4", 14 },
    .{ "a5", 15 },  .{ "a6", 16 }, .{ "a7", 17 }, .{ "s2", 18 },
    .{ "s3", 19 },  .{ "s4", 20 }, .{ "s5", 21 }, .{ "s6", 22 },
    .{ "s7", 23 },  .{ "s8", 24 }, .{ "s9", 25 }, .{ "s10", 26 },
    .{ "s11", 27 }, .{ "t3", 28 }, .{ "t4", 29 }, .{ "t5", 30 },
    .{ "t6", 31 },
});
