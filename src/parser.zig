const std = @import("std");
const mem = std.mem;
const testing = std.testing;

const Tokenizer = @import("tokenizer.zig");
const ArrayList = std.ArrayList;
const StringMap = std.StaticStringMap(u5);

const Self = @This();

tokenizer: Tokenizer,
diagnostics: struct { line: usize = 0, col: usize = 0 } = .{},

pub fn init(program_buffer: []const u8) Self {
    return .{ .tokenizer = .init(program_buffer) };
}

pub fn next(self: *Self) !?Unit {
    errdefer {
        self.diagnostics = .{
            .line = self.tokenizer.line,
            .col = self.tokenizer.col,
        };
    }

    while (try self.tokenizer.next()) |tok| {
        switch (tok) {
            .eof => break,
            .newline => continue,
            .comma, .colon, .minus, .l_paren, .r_paren, .number => return error.MisplacedToken,
            .name => |identifier| {
                return try self.parseIdentifier(identifier);
            },
        }
    }

    return null;
}

fn parseIdentifier(self: *Self, identifier: []const u8) !Unit {
    const next_tok = try self.tokenizer.next() orelse return error.MissingToken;
    switch (next_tok) {
        .colon => return .{ .label_def = identifier },
        .name => |first_operand| {
            const instruction = try self.parseInstruction(identifier, first_operand);
            return .{ .instruction = instruction };
        },
        .eof, .newline => {
            const instruction: Instruction = .{ .mnemonic = identifier };
            return .{ .instruction = instruction };
        },
        else => return error.MisplacedToken,
    }
}

/// If this function returns an error, you may inspect the `diagnostics` field for
/// information about where it occured. It will point you to the end of the offending
/// token if the error name contains "Token", and to the offending character if the
/// error name contains "Character".
/// Helpfulness of this diagnostic information will be highly limited for errors originating
/// at allocation sites.
pub fn parseProgram(self: *Self, gpa: mem.Allocator) !Program {
    var program: Program = .empty;
    errdefer {
        program.deinit(gpa);
        self.diagnostics = .{
            .line = self.tokenizer.line,
            .col = self.tokenizer.col,
        };
    }

    while (try self.tokenizer.next()) |tok| {
        switch (tok) {
            .eof => break,
            .newline => continue,
            .comma, .colon, .minus, .l_paren, .r_paren, .number => return error.MisplacedToken,
            .name => |identifier| {
                const next_tok = try self.tokenizer.next() orelse return error.MissingToken;
                switch (next_tok) {
                    .colon => try program.append(gpa, .{ .label_def = identifier }),
                    .name => |first_operand| {
                        const instruction = try self.parseInstruction(identifier, first_operand);
                        try program.append(gpa, .{ .instruction = instruction });
                    },
                    .eof, .newline => {
                        const instruction: Instruction = .{ .mnemonic = identifier };
                        try program.append(gpa, .{ .instruction = instruction });
                    },
                    else => return error.MisplacedToken,
                }
            },
        }
    }

    return program;
}

fn parseInstruction(
    self: *Self,
    identifier: []const u8,
    first_operand: []const u8,
) !Instruction {
    var instruction: Instruction = .{ .mnemonic = identifier };
    instruction.operands[0] = try parseRegisterOrLabelRef(first_operand);
    instruction.num_operands += 1;
    while (try self.tokenizer.next()) |tok| {
        switch (tok) {
            .newline, .eof => break,
            .comma => {
                if (instruction.num_operands >= 3) return error.TooManyOperandTokens;
                const operand = try self.parseOperand();
                instruction.operands[instruction.num_operands] = operand;
                instruction.num_operands += 1;
            },
            else => return error.MissingToken,
        }
    }

    return instruction;
}

fn parseRegisterOrLabelRef(name: []const u8) !Operand {
    if (reg_aliases.get(name)) |reg| {
        return .{ .register = reg };
    }
    // We allow labels that look like invalid registers,
    // like "x32" or "x150", which might be confusing.
    // Sorry!
    if (name.len > 1 and name[0] == 'x') {
        if (std.fmt.parseInt(u5, name[1..], 10)) |reg| {
            return .{ .register = reg };
        } else |_| {}
    }
    return .{ .label_ref = name };
}

fn parseOperand(self: *Self) !Operand {
    const tok = try self.tokenizer.next() orelse return error.MissingOperandToken;
    var number_multiplier: i32 = 1;
    s: switch (tok) {
        // Handling immediate and memory
        .minus => {
            number_multiplier = -1;
            const next_tok = try self.tokenizer.next() orelse return error.MissingToken;
            if (next_tok != .number) return error.MisplacedToken;
            continue :s next_tok;
        },
        // Also handling immediate and memory
        .number => |num| {
            const immediate: Immediate = num * number_multiplier;
            const next_tok = try self.tokenizer.peekToken();
            if (next_tok) |next_inner| if (next_inner == .l_paren) {
                return self.parseMemory(immediate);
            };
            return .{ .immediate = immediate };
        },
        // Handling register and label_ref
        .name => |str| return parseRegisterOrLabelRef(str),
        .l_paren => return self.parseMemoryNoImmediate(),
        else => return error.MisplacedToken,
    }
}

fn parseMemory(self: *Self, immediate: Immediate) !Operand {
    // We only call this function if we know .next() will return
    // an l_paren token.
    const tok = (self.tokenizer.next() catch unreachable) orelse unreachable;
    std.debug.assert(tok == .l_paren);
    var operand: Operand = try self.parseMemoryNoImmediate();
    operand.memory.immediate = immediate;
    return operand;
}

fn parseMemoryNoImmediate(self: *Self) !Operand {
    const name = try self.tokenizer.next() orelse return error.MissingToken;
    if (name != .name) return error.MisplacedToken;
    const reg = switch (try parseRegisterOrLabelRef(name.name)) {
        .register => |reg| reg,
        else => return error.MisplacedToken,
    };
    if (try self.tokenizer.next()) |r_paren| {
        if (r_paren != .r_paren) return error.MisplacedToken;
    } else return error.MissingToken;
    return .{
        .memory = .{
            .immediate = null,
            .register = reg,
        },
    };
}

pub const Program = ArrayList(Unit);
pub const Unit = union(enum) {
    label_def: []const u8,
    instruction: Instruction,

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        switch (self) {
            .label_def => |label| try writer.print("{s}:", .{label}),
            .instruction => |instruction| try instruction.format(writer),
        }
    }
};
pub const Instruction = struct {
    mnemonic: []const u8,
    operands: [3]Operand = undefined,
    num_operands: u2 = 0,

    pub fn operandsSlice(self: *const Instruction) []const Operand {
        std.debug.assert(self.num_operands <= self.operands.len);
        return self.operands[0..self.num_operands];
    }

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try writer.writeAll(self.mnemonic);
        if (self.num_operands >= 1) try writer.print(" {f}", .{self.operands[0]});
        if (self.num_operands > 1) {
            for (self.operandsSlice()[1..]) |operand| {
                try writer.print(", {f}", .{operand});
            }
        }
    }
};
pub const Operand = union(enum) {
    register: u5,
    memory: Memory,
    immediate: Immediate,
    label_ref: []const u8,

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        switch (self) {
            .register => |reg| try writer.print("x{d}", .{reg}),
            .memory => |memory| {
                if (memory.immediate) |imm| {
                    try writer.print("{d}(x{d})", .{ imm, memory.register });
                } else {
                    try writer.print("(x{d})", .{memory.register});
                }
            },
            .immediate => |imm| try writer.print("{d}", .{imm}),
            .label_ref => |label| try writer.writeAll(label),
        }
    }
};
pub const Memory = struct {
    immediate: ?Immediate,
    register: u5,
};
pub const Immediate = i32;

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

//
//
// TESTS
//
//

test "small Parser smoke test" {
    const program_buf =
        \\add x1, x2, label
        \\word oh, my, 0x100
        \\label:
        \\hello there, how, areya
    ;

    const expecteds: [4]Unit = .{
        .{
            .instruction = .{
                .mnemonic = "add",
                .operands = [3]Operand{
                    .{ .register = 1 },
                    .{ .register = 2 },
                    .{ .label_ref = "label" },
                },
                .num_operands = 3,
            },
        },
        .{
            .instruction = .{
                .mnemonic = "word",
                .operands = [3]Operand{
                    .{ .label_ref = "oh" },
                    .{ .label_ref = "my" },
                    .{ .immediate = 0x100 },
                },
                .num_operands = 3,
            },
        },
        .{
            .label_def = "label",
        },
        .{
            .instruction = .{
                .mnemonic = "hello",
                .operands = [3]Operand{
                    .{ .label_ref = "there" },
                    .{ .label_ref = "how" },
                    .{ .label_ref = "areya" },
                },
                .num_operands = 3,
            },
        },
    };

    var parser: Self = .init(program_buf);
    var i: usize = 0;
    while (try parser.next()) |unit| : (i += 1) try testing.expectEqualDeep(expecteds[i], unit);
}

test "various invalid programs cause Parser errors" {
    const programs: [5][]const u8 = .{
        "ad) x1, x2, x3",
        "add x1 x2, x3",
        "sw x1, -10(x2",
        "(",
        "add x1, x2, x3, x4",
    };

    const expecteds: [5]anyerror = .{
        error.MisplacedToken,
        error.MissingToken,
        error.MisplacedToken,
        error.MisplacedToken,
        error.TooManyOperandTokens,
    };

    for (programs, expecteds) |program, expected| {
        var parser: Self = .init(program);
        try testing.expectError(expected, parser.next());
    }
}
