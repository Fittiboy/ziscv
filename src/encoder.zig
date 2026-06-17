const std = @import("std");
const resolver = @import("resolver.zig");

const ResolvedInstruction = resolver.ResolvedInstruction;

pub fn encodeInstruction(instruction: ResolvedInstruction) MachineInstruction {
    return switch (instruction) {
        .rtype => |r| encodeRType(r),
        .itype => |i| encodeIType(i),
        .stype => |s| encodeSType(s),
        .btype => |b| encodeBType(b),
    };
}

fn encodeRType(r: resolver.RType) MachineInstruction {
    const funct3: u3 = switch (r.mnemonic) {
        .add, .sub => 0,
        .@"and" => 7,
        .@"or" => 6,
        .slt => 2,
        else => unreachable,
    };
    const funct7: u7 = if (r.mnemonic == .sub) 32 else 0;

    return .{
        .rtype = .{
            .op = 51,
            .rd = r.rd,
            .funct3 = funct3,
            .rs1 = r.rs1,
            .rs2 = r.rs2,
            .funct7 = funct7,
        },
    };
}

fn encodeIType(i: resolver.IType) MachineInstruction {
    const op: u7, const funct3: u3 = switch (i.mnemonic) {
        .addi => .{ 19, 0 },
        .lw => .{ 3, 2 },
        else => unreachable,
    };

    return .{
        .itype = .{
            .op = op,
            .rd = i.rd,
            .funct3 = funct3,
            .rs1 = i.rs1,
            .imm12 = @bitCast(i.imm),
        },
    };
}

fn encodeSType(s: resolver.SType) MachineInstruction {
    const Imm = packed union(u12) {
        raw: i12,
        split: packed struct(u12) {
            imm5: u5,
            imm7: u7,
        },
    };

    const imm_structured: Imm = .{ .raw = s.imm };

    return .{
        .stype = .{
            .op = 35,
            .imm5 = imm_structured.split.imm5,
            .funct3 = 2,
            .rs1 = s.rs1,
            .rs2 = s.rs2,
            .imm7 = imm_structured.split.imm7,
        },
    };
}

fn encodeBType(b: resolver.BType) MachineInstruction {
    const Imm = packed union(u13) {
        raw: i13,
        split: packed struct(u13) {
            discard: u1,
            imm4: u4,
            imm6: u6,
            imm1: u1,
            sign: u1,
        },
    };

    const imm_structured: Imm = .{ .raw = b.offset };

    std.debug.assert(imm_structured.split.discard == 0);

    return .{
        .btype = .{
            .op = 99,
            .imm5 = (@as(u5, @intCast(imm_structured.split.imm4)) << 1) + imm_structured.split.imm1,
            .funct3 = 0,
            .rs1 = b.rs1,
            .rs2 = b.rs2,
            .imm7 = (@as(u7, @intCast(imm_structured.split.sign)) << 6) + imm_structured.split.imm6,
        },
    };
}

pub const RType = packed struct(u32) { op: u7, rd: u5, funct3: u3, rs1: u5, rs2: u5, funct7: u7 };
pub const IType = packed struct(u32) { op: u7, rd: u5, funct3: u3, rs1: u5, imm12: u12 };
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
