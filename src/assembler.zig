const std = @import("std");
const ziscv = @import("root.zig");

const r_types = [_][]const u8{ "add", "sub", "and", "or", "slt" };
const i_types = [_][]const u8{"lw"};
const s_types = [_][]const u8{"sw"};
const b_types = [_][]const u8{"beq"};

const Command = enum { add, sub, @"and", @"or", slt, lw, sw, beq };

/// Parses a line of the project's RISC-V Assembly subset into
/// the corresponding machine code instruction.
/// Asserts that the input is not empty.
pub fn parseInstruction(str: []const u8) !ziscv.MachineInstruction {
    std.debug.assert(str.len > 0);
    var tok = std.mem.tokenizeAny(u8, str, ", ");
    const mnemonic = tok.next().?;
    inline for (r_types) |r| {
        if (std.mem.eql(u8, r, mnemonic)) return parseRTypeInstruction(mnemonic, &tok);
    }
    inline for (i_types) |i| {
        if (std.mem.eql(u8, i, mnemonic)) return parseITypeInstruction(mnemonic, &tok);
    }
    inline for (s_types) |s| {
        if (std.mem.eql(u8, s, mnemonic)) return parseSTypeInstruction(mnemonic, &tok);
    }
    inline for (b_types) |b| {
        if (std.mem.eql(u8, b, mnemonic)) return parseBTypeInstruction(mnemonic, &tok);
    }
    return error.InvalidInstruction;
}

fn parseRTypeInstruction(mnemonic: []const u8, tok: *std.mem.TokenIterator(u8, .any)) !ziscv.MachineInstruction {
    const op: u7 = 51;
    const funct3: u3 = blk: {
        const command = std.meta.stringToEnum(Command, mnemonic) orelse unreachable;
        break :blk switch (command) {
            .add, .sub => 0,
            .@"and" => 7,
            .@"or" => 6,
            .slt => 2,
            else => unreachable,
        };
    };
    const funct7: u7 = if (std.mem.eql(u8, mnemonic, "sub")) 32 else 0;

    var registers: [3]u5 = undefined;
    for (0..3) |i| {
        const r_str = tok.next() orelse return error.IncompleteInstruction;
        registers[i] = try parseRegister(r_str);
    }

    if (tok.next()) |_| return error.InvalidInstruction;

    return .{ .rtype = .{
        .op = op,
        .rd = registers[0],
        .funct3 = funct3,
        .rs1 = registers[1],
        .rs2 = registers[2],
        .funct7 = funct7,
    } };
}

fn parseITypeInstruction(mnemonic: []const u8, tok: *std.mem.TokenIterator(u8, .any)) !ziscv.MachineInstruction {
    _ = .{ mnemonic, tok };
    return error.NotImplemented;
}

fn parseSTypeInstruction(mnemonic: []const u8, tok: *std.mem.TokenIterator(u8, .any)) !ziscv.MachineInstruction {
    _ = .{ mnemonic, tok };
    return error.NotImplemented;
}

fn parseBTypeInstruction(mnemonic: []const u8, tok: *std.mem.TokenIterator(u8, .any)) !ziscv.MachineInstruction {
    _ = .{ mnemonic, tok };
    return error.NotImplemented;
}

fn parseRegister(str: []const u8) !u5 {
    if (str.len == 1 or str[0] != 'x') return error.InvalidRD;
    return std.fmt.parseInt(u5, str[1..], 10) catch {
        return error.InvalidRD;
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
