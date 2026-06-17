const std = @import("std");
const mem = std.mem;

const Validator = @import("validator.zig");
const ValidatedUnit = Validator.ValidatedUnit;

pub fn resolveProgram(gpa: mem.Allocator, program: []const ValidatedUnit) ![]const ResolvedInstruction {
    var symbol_table: std.StringHashMapUnmanaged(i33) = .empty;
    defer symbol_table.deinit(gpa);

    // Building the symbol table
    var current_address: i33 = 0;
    for (program) |unit| switch (unit) {
        .instruction => current_address += 4,
        .label_def => |label| {
            try symbol_table.put(gpa, label, current_address);
        },
    };

    // Calculating final offsets, producing program
    var resolved: std.ArrayList(ResolvedInstruction) = .empty;
    errdefer resolved.deinit(gpa);

    current_address = 0;
    for (program) |unit| switch (unit) {
        .instruction => |instruction| {
            try resolved.append(gpa, try resolveInstruction(instruction, current_address, &symbol_table));
            current_address += 4;
        },
        .label_def => continue,
    };

    return resolved.toOwnedSlice(gpa);
}

fn resolveInstruction(
    instruction: Validator.Instruction,
    current_address: i33,
    symbol_table: *std.StringHashMapUnmanaged(i33),
) !ResolvedInstruction {
    return switch (instruction) {
        .rtype, .itype, .stype => .fromValidated(instruction),
        .btype => |b| resolveBType(b, current_address, symbol_table),
    };
}

fn resolveBType(
    b: Validator.BType,
    current_address: i33,
    symbol_table: *std.StringHashMapUnmanaged(i33),
) !ResolvedInstruction {
    const target_addr = symbol_table.get(b.label) orelse return error.ReferencedUndefinedLabel;
    const offset = target_addr - current_address;
    if (offset > std.math.maxInt(i13) or offset < std.math.minInt(i13)) {
        return error.BranchOffsetOutOfRange;
    }
    return .{
        .btype = .{
            .mnemonic = b.mnemonic,
            .rs1 = b.rs1,
            .rs2 = b.rs2,
            .offset = @truncate(offset),
        },
    };
}

pub const ResolvedInstruction = union(enum) {
    rtype: Validator.RType,
    itype: Validator.IType,
    stype: Validator.SType,
    btype: BType,

    fn fromValidated(instruction: Validator.Instruction) @This() {
        return switch (instruction) {
            .rtype => |r| .{ .rtype = r },
            .itype => |i| .{ .itype = i },
            .stype => |s| .{ .stype = s },
            else => unreachable,
        };
    }

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        switch (self) {
            inline else => |inst| try inst.format(writer),
        }
    }
};

pub const RType = Validator.RType;
pub const IType = Validator.IType;
pub const SType = Validator.SType;
pub const BType = struct {
    mnemonic: Validator.Mnemonic,
    rs1: u5,
    rs2: u5,
    offset: i13,

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try writer.print("{s} x{d}, x{d}, {d}", .{
            @tagName(self.mnemonic),
            self.rs1,
            self.rs2,
            self.offset,
        });
    }
};
