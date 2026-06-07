const std = @import("std");
pub const assembler = @import("assembler.zig");

pub const InstructionType = enum { r, i, s, b };

pub const RType = packed struct(u32) { op: u7, rd: u5, funct3: u3, rs1: u5, rs2: u5, funct7: u7 };
pub const IType = packed struct(u32) { op: u7, rd: u5, funct3: u3, rs1: u5, imm: u12 };
pub const SType = packed struct(u32) { op: u7, imm5: u5, funct3: u3, rs1: u5, rs2: u5, imm7: u7 };
pub const BType = packed struct(u32) { op: u7, imm5: u5, funct3: u3, rs1: u5, rs2: u5, imm7: u7 };

pub const MachineInstruction = packed union(u32) {
    raw: u32,
    with_op: packed struct(u32) {
        op: u7,
        raw_rest: u25,
    },
    rtype: RType,
    itype: IType,
    stype: SType,
    btype: BType,
};

pub fn parse(bytes: []const u8, alloc: std.mem.Allocator) ![]MachineInstruction {
    if (bytes.len % 4 != 0) return error.InvalidLength;

    const instructions = try alloc.alloc(MachineInstruction, @divExact(bytes.len, 4));
    errdefer alloc.free(instructions); // Keep this only if anything past this can fail!!

    for (0..bytes.len / 4) |i| {
        const raw_instruction: MachineInstruction = @as(
            *const MachineInstruction,
            @ptrCast(@alignCast(bytes[i * 4 .. (i + 1) * 4].ptr)),
        ).*;
        instructions[i * 4] = .{ .rtype = raw_instruction.rtype };
    }

    return instructions;
}

test {
    _ = @import("assembler.zig");
}

test parse {
    const alloc = std.testing.allocator;

    const bytes = [_]u8{ 0x00, 0xa4, 0x84, 0x33 };
    const instructions: []MachineInstruction = try parse(&bytes, alloc);
    defer alloc.free(instructions);

    try std.testing.expect(instructions.len == 1);
}
