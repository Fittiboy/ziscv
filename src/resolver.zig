const std = @import("std");
const mem = std.mem;
const Parser = @import("parser.zig");

pub fn main(proc_init: std.process.Init) !void {
    const io = proc_init.io;
    const gpa = proc_init.gpa;

    const hello_file = try std.Io.Dir.cwd().openFile(io, "src/hello.s", .{});
    var file_reader_buf: [1024]u8 = undefined;
    var file_reader = hello_file.reader(io, &file_reader_buf);
    const reader = &file_reader.interface;

    const file_buf = try reader.allocRemaining(gpa, .unlimited);
    defer gpa.free(file_buf);

    var resolver: Self = .init(file_buf);
    var program = try resolver.parseAndResolve(gpa);
    defer program.deinit(gpa);

    for (program.program.items) |instruction| {
        std.debug.print("{f}\n", .{instruction});
    }
}

const Self = @This();

program_buffer: []const u8,
diagnostics: struct { line: usize = 0, col: usize = 0 } = .{},

pub fn init(program_buffer: []const u8) Self {
    return .{ .program_buffer = program_buffer };
}

/// After parsing and resolving, the underlying buffer is no longer required,
/// as the instructions are fully within the type system, and slices are
/// discarded. Labels are now simply indices into a numerical symbol table.
/// In case of an error, it might be useful to keep the buffer around to
/// investigate via diagnostics.
pub fn parseAndResolve(self: *Self, gpa: mem.Allocator) !ResolvedProgram {
    var parser: Parser = .init(self.program_buffer);
    errdefer self.diagnostics = .{
        .line = parser.diagnostics.line,
        .col = parser.diagnostics.col,
    };

    var parsed_program = try parser.parseProgram(gpa);
    defer parsed_program.deinit(gpa);

    var symbol_map: SymbolMap = .init(gpa);
    defer symbol_map.deinit();

    return resolveInstructions(gpa, &parsed_program, &symbol_map);
}

pub const SymbolMap = std.StringHashMap(u32);

fn resolveInstructions(
    gpa: mem.Allocator,
    parsed_program: *Parser.Program,
    symbol_map: *SymbolMap,
) !ResolvedProgram {
    var resolved_program: ResolvedProgram = .empty;
    errdefer resolved_program.deinit(gpa);

    var next_address: u32 = 0;

    for (parsed_program.items) |unit| switch (unit) {
        .instruction => |instruction| {
            const validated_instruction = try validateInstruction(instruction);
            try resolved_program.program.append(gpa, validated_instruction);

            next_address += 4;
        },
        .label_def => |label| {
            const entry = try symbol_map.getOrPut(label);
            if (entry.found_existing) return error.DuplicateLabelDefinition;
            entry.value_ptr.* = next_address;
        },
    };

    for (resolved_program.program.items) |*instruction| switch (instruction.*) {
        .btype => |*b| {
            std.debug.assert(b.label == .unresolved);
            const resolved_address: u32 = symbol_map.get(b.label.unresolved) orelse {
                return error.UndefinedLabelReferenced;
            };
            b.label = .{ .resolved = resolved_address };
        },
        else => continue,
    };

    return resolved_program;
}

fn validateInstruction(instruction: Parser.Instruction) !Instruction {
    const mnemonic = std.meta.stringToEnum(Mnemonic, instruction.mnemonic) orelse {
        return error.UnsupportedMnemonic;
    };
    return switch (mnemonic) {
        .add, .sub, .@"or", .@"and", .slt => validateRType(mnemonic, instruction),
        .addi, .lw => validateIType(mnemonic, instruction),
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

fn validateSType(mnemonic: Mnemonic, instruction: Parser.Instruction) !Instruction {
    if (instruction.num_operands != 2) return error.WrongNumberOfOperands;

    const operands = instruction.operandsSlice();
    if (operands[0] != .register) return error.IncorrectOperandType;
    if (operands[1] != .memory) return error.IncorrectOperandType;
    const raw_memory = operands[1].memory;
    const validated_immediate = try validateImmediate(i12, raw_memory.immediate orelse 0);

    return .{
        .stype = .{
            .mnemonic = mnemonic,
            .rs2 = operands[0].register,
            .rs1 = raw_memory.register,
            .imm = validated_immediate,
        },
    };
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
            .label = .{
                .unresolved = operands[2].label_ref,
            },
        },
    };
}

fn validateImmediate(comptime T: type, imm: Parser.Immediate) !T {
    if (imm > std.math.maxInt(T)) return error.ImmediateTooLarge;
    return @truncate(imm);
}

pub const ResolvedProgram = struct {
    program: std.ArrayList(Instruction),

    pub const empty: @This() = .{ .program = .empty };

    pub fn deinit(self: *@This(), gpa: mem.Allocator) void {
        self.program.deinit(gpa);
        self.* = undefined;
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
pub const RType = struct {
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
pub const IType = struct {
    mnemonic: Mnemonic,
    rd: u5,
    rs1: u5,
    imm: i12,

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try writer.print("{s} x{d}, x{d}, {d}", .{
            @tagName(self.mnemonic),
            self.rd,
            self.rs1,
            self.imm,
        });
    }
};
pub const SType = struct {
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
pub const BType = struct {
    mnemonic: Mnemonic,
    rs1: u5,
    rs2: u5,
    label: union(enum) {
        unresolved: []const u8,
        resolved: u32,
    },

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        switch (self.label) {
            .unresolved => |str| try writer.print("{s} x{d}, x{d}, {s}", .{
                @tagName(self.mnemonic),
                self.rs1,
                self.rs2,
                str,
            }),
            .resolved => |imm| try writer.print("{s} x{d}, x{d}, {d}", .{
                @tagName(self.mnemonic),
                self.rs1,
                self.rs2,
                imm,
            }),
        }
    }
};
pub const Memory = struct {
    immediate: i12,
    register: u5,
};
