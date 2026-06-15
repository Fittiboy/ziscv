const std = @import("std");
const mem = std.mem;
const testing = std.testing;

const Parser = @import("parser.zig");

const Self = @This();

parser: Parser,
label_map: std.StringHashMapUnmanaged(void) = .empty,
diagnostics: struct { line: usize = 0, col: usize = 0 } = .{},

/// The `Parser` carries a label map for validation, which needs to
/// be deinitialized after work is done.
pub fn init(program_buffer: []const u8) Self {
    return .{ .parser = .init(program_buffer) };
}

pub fn deinit(self: *Self, gpa: mem.Allocator) void {
    self.label_map.deinit(gpa);
    self.* = undefined;
}

/// The allocator is needed for label map allocations, to keep
/// track of possibly duplicate label definitions.
pub fn next(self: *Self, gpa: mem.Allocator) !?ValidatedUnit {
    errdefer self.diagnostics = .{
        .line = self.parser.diagnostics.line,
        .col = self.parser.diagnostics.col,
    };

    const unit = try self.parser.next() orelse return null;
    return try self.validateUnit(gpa, unit);
}

fn validateUnit(self: *Self, gpa: mem.Allocator, unit: Parser.Unit) !ValidatedUnit {
    return switch (unit) {
        .instruction => |instruction| .{ .instruction = try validateInstruction(instruction) },
        .label_def => |label| self.validateLabel(gpa, label),
    };
}

fn validateLabel(self: *Self, gpa: mem.Allocator, label: []const u8) !ValidatedUnit {
    const entry = try self.label_map.getOrPut(gpa, label);
    if (entry.found_existing) return error.DuplicateLabelDefinition;
    return .{ .label_def = label };
}

fn validateInstruction(instruction: Parser.Instruction) !Instruction {
    const mnemonic = std.meta.stringToEnum(Mnemonic, instruction.mnemonic) orelse {
        return error.UnsupportedMnemonic;
    };
    return switch (mnemonic) {
        .add, .sub, .@"or", .@"and", .slt => validateRType(mnemonic, instruction),
        .addi => validateIType(mnemonic, instruction),
        .lw => validateLoad(mnemonic, instruction),
        .sw => validateSType(mnemonic, instruction),
        .beq => validateBType(mnemonic, instruction),
    };
}

fn validateRType(mnemonic: Mnemonic, instruction: Parser.Instruction) !Instruction {
    if (instruction.num_operands != 3) return error.WrongNumberOfOperands;

    const operands = instruction.operandsSlice();
    for (operands) |operand| switch (operand) {
        .register => continue,
        else => return error.IncorrectOperandType,
    };

    return .{
        .rtype = .{
            .mnemonic = mnemonic,
            .rd = operands[0].register,
            .rs1 = operands[1].register,
            .rs2 = operands[2].register,
        },
    };
}

fn validateIType(mnemonic: Mnemonic, instruction: Parser.Instruction) !Instruction {
    if (instruction.num_operands != 3) return error.WrongNumberOfOperands;

    const operands = instruction.operandsSlice();
    if (operands[0] != .register) return error.IncorrectOperandType;
    if (operands[1] != .register) return error.IncorrectOperandType;
    if (operands[2] != .immediate) return error.IncorrectOperandType;
    const validated_immediate = try validateImmediate(i12, operands[2].immediate);

    return .{
        .itype = .{
            .mnemonic = mnemonic,
            .rd = operands[0].register,
            .rs1 = operands[1].register,
            .imm = validated_immediate,
        },
    };
}

fn validateLoad(mnemonic: Mnemonic, instruction: Parser.Instruction) !Instruction {
    const raw_memory, const validated_immediate = try validateLoadOrStore(instruction);
    return .{
        .itype = .{
            .mnemonic = mnemonic,
            .rd = instruction.operandsSlice()[0].register,
            .rs1 = raw_memory.register,
            .imm = validated_immediate,
        },
    };
}

fn validateSType(mnemonic: Mnemonic, instruction: Parser.Instruction) !Instruction {
    const raw_memory, const validated_immediate = try validateLoadOrStore(instruction);
    return .{
        .stype = .{
            .mnemonic = mnemonic,
            .rs2 = instruction.operandsSlice()[0].register,
            .rs1 = raw_memory.register,
            .imm = validated_immediate,
        },
    };
}

fn validateLoadOrStore(instruction: Parser.Instruction) !struct { Parser.Memory, i12 } {
    if (instruction.num_operands != 2) return error.WrongNumberOfOperands;

    const operands = instruction.operandsSlice();
    if (operands[0] != .register) return error.IncorrectOperandType;
    if (operands[1] != .memory) return error.IncorrectOperandType;
    const raw_memory = operands[1].memory;
    const validated_immediate = try validateImmediate(i12, raw_memory.immediate orelse 0);
    return .{ raw_memory, validated_immediate };
}

fn validateBType(mnemonic: Mnemonic, instruction: Parser.Instruction) !Instruction {
    if (instruction.num_operands != 3) return error.WrongNumberOfOperands;

    const operands = instruction.operandsSlice();
    if (operands[0] != .register) return error.IncorrectOperandType;
    if (operands[1] != .register) return error.IncorrectOperandType;
    if (operands[2] != .label_ref) return error.IncorrectOperandType;

    return .{
        .btype = .{
            .mnemonic = mnemonic,
            .rs1 = operands[0].register,
            .rs2 = operands[1].register,
            .label = operands[2].label_ref,
        },
    };
}

fn validateImmediate(comptime T: type, imm: Parser.Immediate) !T {
    if (imm > std.math.maxInt(T)) return error.ImmediateTooLarge;
    if (imm < std.math.minInt(T)) return error.ImmediateTooSmall;
    return @truncate(imm);
}

pub const ValidatedUnit = union(enum) {
    instruction: Instruction,
    label_def: []const u8,

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        switch (self) {
            .instruction => |instruction| try instruction.format(writer),
            .label_def => |label| try writer.print("{s}:", .{label}),
        }
    }
};

pub const Mnemonic = enum {
    add,
    sub,
    @"or",
    @"and",
    slt,
    addi,
    lw,
    sw,
    beq,
};

pub const Instruction = union(enum) {
    rtype: RType,
    itype: IType,
    stype: SType,
    btype: BType,

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        switch (self) {
            inline else => |inst| try inst.format(writer),
        }
    }
};
const RType = struct {
    mnemonic: Mnemonic,
    rd: u5,
    rs1: u5,
    rs2: u5,

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try writer.print("{s} x{d}, x{d}, x{d}", .{
            @tagName(self.mnemonic),
            self.rd,
            self.rs1,
            self.rs2,
        });
    }
};
const IType = struct {
    mnemonic: Mnemonic,
    rd: u5,
    rs1: u5,
    imm: i12,

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        switch (self.mnemonic) {
            .lw => try writer.print("{s} x{d}, {d}(x{d})", .{
                @tagName(self.mnemonic),
                self.rd,
                self.imm,
                self.rs1,
            }),
            else => try writer.print("{s} x{d}, x{d}, {d}", .{
                @tagName(self.mnemonic),
                self.rd,
                self.rs1,
                self.imm,
            }),
        }
    }
};
const SType = struct {
    mnemonic: Mnemonic,
    rs2: u5,
    rs1: u5,
    imm: i12,

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try writer.print("{s} x{d}, {d}(x{d})", .{
            @tagName(self.mnemonic),
            self.rs2,
            self.imm,
            self.rs1,
        });
    }
};
const BType = struct {
    mnemonic: Mnemonic,
    rs1: u5,
    rs2: u5,
    label: []const u8,

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try writer.print("{s} x{d}, x{d}, {s}", .{
            @tagName(self.mnemonic),
            self.rs1,
            self.rs2,
            self.label,
        });
    }
};
const Memory = struct {
    immediate: i12,
    register: u5,
};

//
//
// TESTS
//
//

test "small Validator smoke test" {
    const program =
        \\addi sp, sp, -16
        \\sw s0, 12(sp)
    ;

    const expecteds = [_]ValidatedUnit{
        .{
            .instruction = .{
                .itype = .{
                    .mnemonic = .addi,
                    .rd = 2,
                    .rs1 = 2,
                    .imm = -16,
                },
            },
        },
        .{
            .instruction = .{
                .stype = .{
                    .mnemonic = .sw,
                    .rs2 = 8,
                    .rs1 = 2,
                    .imm = 12,
                },
            },
        },
    };

    const gpa = testing.allocator;
    var validator: Self = .init(program);
    defer validator.deinit(gpa);
    var i: usize = 0;
    while (try validator.next(gpa)) |unit| : (i += 1) {
        try testing.expectEqualDeep(expecteds[i], unit);
    }
}
