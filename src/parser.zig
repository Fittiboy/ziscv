const std = @import("std");
const mem = std.mem;

const Tokenizer = @import("tokenizer.zig");
const ArrayList = std.ArrayList;
const StringMap = std.StaticStringMap(u5);

pub fn main(proc_init: std.process.Init) !void {
    const io = proc_init.io;
    const gpa = proc_init.gpa;

    const hello_file = try std.Io.Dir.cwd().openFile(io, "src/hello.s", .{});
    var file_reader_buf: [1024]u8 = undefined;
    var file_reader = hello_file.reader(io, &file_reader_buf);
    const reader = &file_reader.interface;

    const file_buf = try reader.allocRemaining(gpa, .unlimited);
    defer gpa.free(file_buf);

    var parser = init(file_buf);

    var program = try parser.parseProgram(gpa);
    defer program.deinit(gpa);

    for (program.items) |unit| {
        std.debug.print("{f}\n", .{unit});
    }
}

const Self = @This();

tokenizer: Tokenizer,
diagnostics: struct { line: usize = 0, col: usize = 0 } = .{},

pub fn init(program_buffer: []const u8) Self {
    return .{ .tokenizer = .init(program_buffer) };
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
                const next = try self.tokenizer.next() orelse return error.MissingToken;
                switch (next) {
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
            else => return error.MisplacedToken,
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
            const next = try self.tokenizer.next() orelse return error.MissingToken;
            if (next != .number) return error.InvalidToken;
            continue :s next;
        },
        // Also handling immediate and memory
        .number => |num| {
            const immediate: Immediate = num * number_multiplier;
            const next = try self.tokenizer.peekToken();
            if (next) |next_tok| if (next_tok == .l_paren) {
                return self.parseMemory(immediate);
            };
            return .{ .immediate = immediate };
        },
        // Handling register and label_ref
        .name => |str| return parseRegisterOrLabelRef(str),
        else => return error.InvalidToken,
    }
}

fn parseMemory(self: *Self, immediate: Immediate) !Operand {
    // We only call this if we know .next() will return
    // an l_paren token.
    _ = self.tokenizer.next() catch {};
    const name = try self.tokenizer.next() orelse return error.MissingToken;
    if (name != .name) return error.InvalidToken;
    const reg = switch (try parseRegisterOrLabelRef(name.name)) {
        .register => |reg| reg,
        else => return error.InvalidToken,
    };
    if (try self.tokenizer.next()) |r_paren| {
        if (r_paren != .r_paren) return error.InvalidToken;
    } else return error.MissingToken;
    return .{
        .memory = .{
            .immediate = immediate,
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

    pub fn operandsSlice(self: Instruction) []const Operand {
        return self.operands[0..self.num_operands];
    }

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try writer.writeAll(self.mnemonic);
        if (self.num_operands >= 1) try writer.print(" {f}", .{self.operands[0]});
        if (self.num_operands > 1) {
            for (1..self.num_operands) |i| {
                try writer.print(", {f}", .{self.operands[i]});
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
                try writer.print("{d}(x{d})", .{ memory.immediate, memory.register });
            },
            .immediate => |imm| try writer.print("{d}", .{imm}),
            .label_ref => |label| try writer.writeAll(label),
        }
    }
};
pub const Memory = struct {
    immediate: Immediate,
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
