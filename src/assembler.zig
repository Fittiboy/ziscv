const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    var args_iter = try init.minimal.args.iterateAllocator(gpa);
    defer args_iter.deinit();
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

    try parseProgram(reader, stdout);
}

const ParserError = error{
    InvalidInstruction,
    IncompleteInstruction,
    InvalidRegister,
    LineTooLong,
    WriteFailed,
};

pub const Command = enum { add, sub, @"or", @"and", slt, addi, lw, sw, beq };

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

/// Parses an entire program, assuming each line contains an instruction.
/// Comments are allowed, but have to share a line with an instruction.
/// Labels are not supported, and neither are register names other than
/// the default x0-x31.
pub fn parseProgram(prog_reader: *std.Io.Reader, prog_writer: *std.Io.Writer) ParserError!void {
    while (prog_reader.takeDelimiter('\n') catch return ParserError.LineTooLong) |l| {
        const instruction = try parseInstruction(l);
        try prog_writer.writeAll(&@as([4]u8, @bitCast(instruction)));
        try prog_writer.flush();
    } else return;
}

/// Parses a line of the project's RISC-V Assembly subset into
/// the corresponding machine code instruction.
/// Asserts that the input is not empty.
pub fn parseInstruction(str: []const u8) ParserError!MachineInstruction {
    std.debug.assert(str.len > 0);
    var tok = std.mem.tokenizeAny(u8, str, ", ");
    const mnemonic = std.meta.stringToEnum(Command, tok.next().?) orelse return error.InvalidInstruction;
    return switch (mnemonic) {
        .add, .sub, .@"and", .@"or", .slt => parseRTypeInstruction(mnemonic, &tok),
        .lw, .addi => parseITypeInstruction(mnemonic, &tok),
        .sw => parseSTypeInstruction(mnemonic, &tok),
        .beq => parseBTypeInstruction(mnemonic, &tok),
    };
}

fn parseRTypeInstruction(mnemonic: Command, tok: *std.mem.TokenIterator(u8, .any)) ParserError!MachineInstruction {
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
) ParserError!MachineInstruction {
    const op: u7, const funct3: u3 = switch (mnemonic) {
        .addi => .{ 19, 0 },
        .lw => .{ 3, 2 },
        else => unreachable,
    };

    var registers: [2]u5 = undefined;

    const rd_str = tok.next() orelse return ParserError.IncompleteInstruction;
    registers[0] = try parseRegister(rd_str);

    const imm12, registers[1] = switch (mnemonic) {
        .addi => blk: {
            const rs1_str = tok.next() orelse return ParserError.IncompleteInstruction;
            const rs1 = try parseRegister(rs1_str);
            const imm12_str = tok.next() orelse return ParserError.IncompleteInstruction;
            break :blk .{
                std.fmt.parseInt(i12, imm12_str, 10) catch {
                    return ParserError.InvalidInstruction;
                },
                rs1,
            };
        },
        .lw => blk: {
            const imm_rs1_str = tok.next() orelse return ParserError.IncompleteInstruction;
            break :blk try parseImmOffsetRegister(i12, imm_rs1_str);
        },
        else => unreachable,
    };

    if (tok.next()) |str| if (str[0] != '#') return ParserError.InvalidInstruction;

    return .{ .itype = .{
        .op = op,
        .rd = registers[0],
        .funct3 = funct3,
        .rs1 = registers[1],
        .imm12 = @bitCast(imm12),
    } };
}

fn parseSTypeInstruction(
    mnemonic: Command,
    tok: *std.mem.TokenIterator(u8, .any),
) ParserError!MachineInstruction {
    _ = mnemonic;

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
        .funct3 = 2,
        .rs1 = registers[1],
        .rs2 = registers[0],
        .imm7 = imm_structured.split.imm7,
    } };
}

fn parseBTypeInstruction(
    mnemonic: Command,
    tok: *std.mem.TokenIterator(u8, .any),
) ParserError!MachineInstruction {
    _ = mnemonic;

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
        .funct3 = 0,
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

// -------------------------------------------
// |                                         |
// |             THE TEST ZONE               |
// |                                         |
// -------------------------------------------

test parseProgram {
    const program =
        \\add x0, x1, x2
        \\sub x3, x4, x5
        \\lw x0, 115(x1)
        \\addi x3 x3 -133 # Comments allowed, commas can be ignored!
        \\sw x0, 115(x1) # With comment
        \\sw x3 -133(x4) # Missing commas are fine
        \\beq x27, x23, -12
        \\beq x22, x0, 116 # Comment? Yes, please!
    ;
    var prog_reader: std.Io.Reader = .fixed(program[0..program.len]);

    var machine_code: [8 * 4]u8 = undefined;
    var machine_code_writer: std.Io.Writer = .fixed(&machine_code);

    try parseProgram(&prog_reader, &machine_code_writer);

    const expected: [8 * 4]u8 = [_]u8{
        0x33, 0x80, 0x20, 0x00,
        0xb3, 0x01, 0x52, 0x40,
        0x03, 0xa0, 0x30, 0x07,
        0x93, 0x81, 0xb1, 0xf7,
        0xa3, 0xa9, 0x00, 0x06,
        0xa3, 0x2d, 0x32, 0xf6,
        0xe3, 0x8a, 0x7d, 0xff,
        0x63, 0x0a, 0x0b, 0x06,
    };

    try std.testing.expectEqualStrings(&expected, &machine_code);
}

test parseInstruction {
    const instruction = try parseInstruction("add x0, x1, x2");

    try std.testing.expectEqual(0x00208033, instruction.raw);
}

test parseRTypeInstruction {
    const instructions = [_][]const u8{
        "add x0, x1, x2",
        "sub x3, x4, x5",
        "and x6, x7, x12 # Comments allowed!",
        "or  x3 x8 x27 # Commas not needed!",
        "slt x5, x14, x21",
    };

    const expected = [_]MachineInstruction{
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
        "addi x3 x3 -133 # Comments allowed, commas can be ignored!",
    };

    const expected = [_]MachineInstruction{
        .{ .raw = 0x0730a003 },
        .{ .raw = 0xf7b18193 },
    };

    for (instructions, expected) |i, e| {
        try std.testing.expectEqual(e, try parseInstruction(i));
    }
}

test parseSTypeInstruction {
    const instructions = [_][]const u8{
        "sw x0, 115(x1) # With comment",
        "sw x3 -133(x4) # Missing commas are fine",
    };

    const expected = [_]MachineInstruction{
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
        "beq x22, x0, 116 # Comment? Yes, please!",
        "beq x4 x1 1700 # Commas? No thank you!",
    };

    const expected = [_]MachineInstruction{
        .{ .raw = 0xff7d8ae3 },
        .{ .raw = 0x060b0a63 },
        .{ .raw = 0x6a120263 },
    };

    for (instructions, expected) |i, e| {
        try std.testing.expectEqual(e, try parseInstruction(i));
    }
}

test "fuzz instruction parser valid" {
    try std.testing.fuzz({}, fuzzParser, .{});
}

fn fuzzParser(_: void, smith: *std.testing.Smith) !void {
    var buf: [24]u8 = undefined;
    var len: usize = 0;

    const command = smith.value(Command);
    const cmd_str = @tagName(command);
    for (cmd_str) |c| {
        buf[len] = c;
        len += 1;
    }
    buf[len] = ' ';
    len += 1;

    // All instructions include one register after
    // the mnemonic.
    len += printRegister(buf[len..], smith, .comma);

    switch (command) {
        .add, .sub, .@"and", .@"or", .slt => {
            len += printRegister(buf[len..], smith, .comma);
            len += printRegister(buf[len..], smith, .no_comma);
        },
        .lw, .sw => {
            const imm = smith.value(i12);
            len += std.fmt.printInt(buf[len..], imm, 10, .lower, .{});
            buf[len] = '(';
            len += 1;
            len += printRegister(buf[len..], smith, .no_comma);
            buf[len] = ')';
            len += 1;
        },
        .beq => {
            len += printRegister(buf[len..], smith, .comma);
            const imm: i13 = @as(i13, @intCast(smith.value(i12))) << 1;
            len += std.fmt.printInt(buf[len..], imm, 10, .lower, .{});
        },
        .addi => {
            len += printRegister(buf[len..], smith, .comma);
            const imm: i12 = smith.value(i12);
            len += std.fmt.printInt(buf[len..], imm, 10, .lower, .{});
        },
    }

    // if (!@import("builtin").fuzz) {
    //     std.debug.print("Regression test for : '{s}'\n", .{buf[0..len]});
    // }

    _ = try parseInstruction(buf[0..len]);
}

fn printRegister(
    buf: []u8,
    smith: *std.testing.Smith,
    end: enum { comma, no_comma },
) usize {
    var len: usize = 0;
    buf[0] = 'x';
    len += 1;
    len += std.fmt.printInt(buf[len..], smith.value(u5), 10, .lower, .{});
    switch (end) {
        .comma => {
            buf[len] = ',';
            buf[len + 1] = ' ';
            len += 2;
        },
        .no_comma => {},
    }
    return len;
}

test "fuzz instruction parser random bytes" {
    try std.testing.fuzz({}, fuzzParserGarbage, .{});
}

fn fuzzParserGarbage(_: void, smith: *std.testing.Smith) !void {
    var buf: [24]u8 = undefined;
    smith.bytes(&buf);
    _ = parseInstruction(&buf) catch return;
}
