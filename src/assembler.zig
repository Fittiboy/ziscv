const std = @import("std");
const ziscv = @import("root.zig");

const ParserError = error{
    InvalidInstruction,
    IncompleteInstruction,
    InvalidRegister,
};

const Command = enum { add, sub, @"and", @"or", slt, lw, sw, beq };

/// Parses a line of the project's RISC-V Assembly subset into
/// the corresponding machine code instruction.
/// Asserts that the input is not empty.
pub fn parseInstruction(str: []const u8) ParserError!ziscv.MachineInstruction {
    std.debug.assert(str.len > 0);
    var tok = std.mem.tokenizeAny(u8, str, ", ");
    const mnemonic = std.meta.stringToEnum(Command, tok.next().?) orelse return error.InvalidInstruction;
    return switch (mnemonic) {
        .add, .sub, .@"and", .@"or", .slt => parseRTypeInstruction(mnemonic, &tok),
        .lw => parseITypeInstruction(mnemonic, &tok),
        .sw => parseSTypeInstruction(mnemonic, &tok),
        .beq => parseBTypeInstruction(mnemonic, &tok),
    };
}

fn parseRTypeInstruction(mnemonic: Command, tok: *std.mem.TokenIterator(u8, .any)) ParserError!ziscv.MachineInstruction {
    const funct3: u3 = switch (mnemonic) {
        .add, .sub => 0,
        .@"and" => 7,
        .@"or" => 6,
        .slt => 2,
        else => unreachable,
    };
    const funct7: u7 = if (mnemonic == .sub) 32 else 0;

    var registers: [3]u5 = undefined;
    for (0..3) |i| {
        const r_str = tok.next() orelse return error.IncompleteInstruction;
        registers[i] = try parseRegister(r_str);
    }

    if (tok.next()) |str| if (str[0] != '#') return error.InvalidInstruction;

    return .{ .rtype = .{
        .op = 51,
        .rd = registers[0],
        .funct3 = funct3,
        .rs1 = registers[1],
        .rs2 = registers[2],
        .funct7 = funct7,
    } };
}

fn parseImmOffsetRegister(comptime ImmType: type, str: []const u8) ParserError!@Tuple(&.{ ImmType, u5 }) {
    comptime std.debug.assert(ImmType == i12 or ImmType == i13 or ImmType == i20);
    const paren_idx = std.mem.findScalar(u8, str, '(') orelse return ParserError.IncompleteInstruction;
    const imm: ImmType = std.fmt.parseInt(ImmType, str[0..paren_idx], 10) catch {
        return ParserError.InvalidInstruction;
    };
    //
    // The shortest legal length is when there is at least 'x0)' following the
    // opening parenthesis.
    if (str.len < paren_idx + 4) return ParserError.IncompleteInstruction;
    const register: u5 = try parseRegister(str[paren_idx + 1 .. str.len - 1]);

    return .{ imm, register };
}

fn parseITypeInstruction(
    mnemonic: Command,
    tok: *std.mem.TokenIterator(u8, .any),
) ParserError!ziscv.MachineInstruction {
    const funct3: u3 = switch (mnemonic) {
        .lw => 2,
        else => unreachable,
    };

    var registers: [2]u5 = undefined;

    const rd_str = tok.next() orelse return ParserError.IncompleteInstruction;
    registers[0] = try parseRegister(rd_str);

    const imm_rs1_str = tok.next() orelse return ParserError.IncompleteInstruction;
    const imm12: i12, registers[1] = try parseImmOffsetRegister(i12, imm_rs1_str);

    if (tok.next()) |str| if (str[0] != '#') return ParserError.InvalidInstruction;

    return .{ .itype = .{
        .op = 3,
        .rd = registers[0],
        .funct3 = funct3,
        .rs1 = registers[1],
        .imm12 = @bitCast(imm12),
    } };
}

fn parseSTypeInstruction(
    mnemonic: Command,
    tok: *std.mem.TokenIterator(u8, .any),
) ParserError!ziscv.MachineInstruction {
    const funct3: u3 = switch (mnemonic) {
        .sw => 2,
        else => unreachable,
    };

    var registers: [2]u5 = undefined;

    const rs2_str = tok.next() orelse return ParserError.IncompleteInstruction;
    registers[0] = try parseRegister(rs2_str);

    const imm_rs1_str = tok.next() orelse return ParserError.IncompleteInstruction;
    const imm12: i12, registers[1] = try parseImmOffsetRegister(i12, imm_rs1_str);

    const Imm = packed union(u12) {
        raw: i12,
        split: packed struct(u12) {
            imm5: u5,
            imm7: u7,
        },
    };

    const imm_structured: Imm = .{ .raw = imm12 };

    return .{ .stype = .{
        .op = 35,
        .imm5 = imm_structured.split.imm5,
        .funct3 = funct3,
        .rs1 = registers[1],
        .rs2 = registers[0],
        .imm7 = imm_structured.split.imm7,
    } };
}

fn parseBTypeInstruction(
    mnemonic: Command,
    tok: *std.mem.TokenIterator(u8, .any),
) ParserError!ziscv.MachineInstruction {
    const funct3: u3 = switch (mnemonic) {
        .beq => 0,
        else => unreachable,
    };

    var registers: [2]u5 = undefined;
    for (0..2) |i| {
        const r_str = tok.next() orelse return error.IncompleteInstruction;
        registers[i] = try parseRegister(r_str);
    }

    const imm_str = tok.next() orelse return ParserError.IncompleteInstruction;
    const imm13: i13 = std.fmt.parseInt(i13, imm_str, 10) catch {
        return ParserError.InvalidInstruction;
    };

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

    const imm_structured: Imm = .{ .raw = imm13 };

    if (imm_structured.split.discard != 0) return ParserError.InvalidInstruction;

    return .{ .btype = .{
        .op = 99,
        .imm5 = (@as(u5, @intCast(imm_structured.split.imm4)) << 1) + imm_structured.split.imm1,
        .funct3 = funct3,
        .rs1 = registers[0],
        .rs2 = registers[1],
        .imm7 = (@as(u7, @intCast(imm_structured.split.sign)) << 6) + imm_structured.split.imm6,
    } };
}

fn parseRegister(str: []const u8) ParserError!u5 {
    if (str.len == 1 or str[0] != 'x') return ParserError.InvalidRegister;
    return std.fmt.parseInt(u5, str[1..], 10) catch {
        return error.InvalidRegister;
    };
}

test parseInstruction {
    const instruction = try parseInstruction("add x0, x1, x2");

    try std.testing.expectEqual(0x00208033, instruction.raw);
}

test parseRTypeInstruction {
    const instructions = [_][]const u8{
        "add x0, x1, x2",
        "sub x3, x4, x5",
        "and x6, x7, x12",
        "or  x3, x8, x27",
        "slt x5, x14, x21",
    };

    const expected = [_]ziscv.MachineInstruction{
        .{ .raw = 0x00208033 },
        .{ .raw = 0x405201b3 },
        .{ .raw = 0x00c3f333 },
        .{ .raw = 0x01b461b3 },
        .{ .raw = 0x015722b3 },
    };

    for (instructions, expected) |i, e| {
        try std.testing.expectEqual(e, try parseInstruction(i));
    }
}

test parseITypeInstruction {
    const instructions = [_][]const u8{
        "lw x0, 115(x1)",
        "lw x3, -133(x4)",
    };

    const expected = [_]ziscv.MachineInstruction{
        .{ .raw = 0x0730a003 },
        .{ .raw = 0xf7b22183 },
    };

    for (instructions, expected) |i, e| {
        try std.testing.expectEqual(e, try parseInstruction(i));
    }
}

test parseSTypeInstruction {
    const instructions = [_][]const u8{
        "sw x0, 115(x1)",
        "sw x3, -133(x4)",
    };

    const expected = [_]ziscv.MachineInstruction{
        .{ .raw = 0x0600a9a3 },
        .{ .raw = 0xf6322da3 },
    };

    for (instructions, expected) |i, e| {
        try std.testing.expectEqual(e, try parseInstruction(i));
    }
}

test parseBTypeInstruction {
    const instructions = [_][]const u8{
        "beq x27, x23, -12",
        "beq x22, x0, 116",
        "beq x4, x1, 1700",
    };

    const expected = [_]ziscv.MachineInstruction{
        .{ .raw = 0xff7d8ae3 },
        .{ .raw = 0x060b0a63 },
        .{ .raw = 0x6a120263 },
    };

    for (instructions, expected) |i, e| {
        try std.testing.expectEqual(e, try parseInstruction(i));
    }
}

test "fuzz instruction parser" {
    try std.testing.fuzz({}, fuzzParser, .{ .corpus = &.{
        @embedFile("testcases/parser-01"),
    } });
}

fn fuzzParser(_: void, smith: *std.testing.Smith) !void {
    var buf: [24]u8 = undefined;
    var len: usize = 0;

    @memcpy(buf[0..4], "add ");
    len += 4;
    for (0..3) |i| {
        buf[len] = 'x';
        len += 1;
        len += std.fmt.printInt(
            buf[len..],
            smith.value(u5),
            10,
            .lower,
            .{},
        );
        if (i == 2) break;
        buf[len] = ',';
        buf[len + 1] = ' ';
        len += 2;
    }

    // if (!@import("builtin").fuzz) {
    //     std.debug.print("{s}\n", .{buf[0..len]});
    // }

    _ = try parseInstruction(buf[0..len]);
}
