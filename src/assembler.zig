const std = @import("std");
const ziscv = @import("root.zig");

const ParserError = error{
    InvalidInstruction,
    IncompleteInstruction,
    InvalidRegister,
    /// Get rid of this!!!
    NotImplemented,
};

const r_types = [_][]const u8{ "add", "sub", "and", "or", "slt" };
const i_types = [_][]const u8{"lw"};
const s_types = [_][]const u8{"sw"};
const b_types = [_][]const u8{"beq"};

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

fn parseITypeInstruction(mnemonic: Command, tok: *std.mem.TokenIterator(u8, .any)) ParserError!ziscv.MachineInstruction {
    const funct3: u3 = switch (mnemonic) {
        .lw => 2,
        else => unreachable,
    };

    var registers: [2]u5 = undefined;

    const rd_str = tok.next() orelse return ParserError.IncompleteInstruction;
    registers[0] = try parseRegister(rd_str);

    const imm_rs_str = tok.next() orelse return ParserError.IncompleteInstruction;
    const paren_idx = std.mem.findScalar(u8, imm_rs_str, '(') orelse return ParserError.IncompleteInstruction;
    const imm12: i12 = std.fmt.parseInt(i12, imm_rs_str[0..paren_idx], 10) catch {
        return ParserError.InvalidInstruction;
    };

    // The shortest legal length is when there is at least 'x0)' following the
    // opening parenthesis.
    if (imm_rs_str.len < paren_idx + 4) return ParserError.IncompleteInstruction;
    registers[1] = try parseRegister(imm_rs_str[paren_idx + 1 .. imm_rs_str.len - 1]);

    if (tok.next()) |str| if (str[0] != '#') return ParserError.InvalidInstruction;

    return .{ .itype = .{
        .op = 3,
        .rd = registers[0],
        .funct3 = funct3,
        .rs1 = registers[1],
        .imm12 = imm12,
    } };
}

fn parseSTypeInstruction(mnemonic: Command, tok: *std.mem.TokenIterator(u8, .any)) ParserError!ziscv.MachineInstruction {
    _ = .{ mnemonic, tok };
    return error.NotImplemented;
}

fn parseBTypeInstruction(mnemonic: Command, tok: *std.mem.TokenIterator(u8, .any)) ParserError!ziscv.MachineInstruction {
    _ = .{ mnemonic, tok };
    return error.NotImplemented;
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
