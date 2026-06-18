const std = @import("std");
const file_helper = @import("file_helper.zig");
const encoder = @import("encoder.zig");

const MachineInstruction = encoder.MachineInstruction;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    const file = try file_helper.openInputFile(init, io, gpa);
    defer file.close(io);

    var reader_buf: [1024]u8 = undefined;
    var file_reader = file.reader(io, &reader_buf);
    const reader: *std.Io.Reader = &file_reader.interface;

    var stdout_buf: [1024]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), io, &stdout_buf);
    const stdout: *std.Io.Writer = &stdout_writer.interface;

    var machine: Machine = try .fromProgramReader(reader);

    try machine.simulate();

    try stdout.writeAll(&machine.memory);
    try stdout.flush();
}

pub const Machine = struct {
    const Self = @This();

    prog_len: usize = 0,
    pc: u32 = 0x00000000,
    register_bank: [32]i32 = @splat(0x00000000),
    memory: [32 * 4 * 1024]u8 = undefined,

    pub const Command = enum { add, sub, @"or", @"and", slt, addi, lw, sw, beq };
    const Instruction = union(enum) {
        rtype: struct { cmd: Command, rd: u5, rs1: u5, rs2: u5 },
        itype: struct { cmd: Command, rd: u5, rs1: u5, imm12: i12 },
        stype: struct { cmd: Command, rs1: u5, rs2: u5, offset: i12 },
        btype: struct { cmd: Command, rs1: u5, rs2: u5, offset: i13 },
    };

    const fresh: Self = .{};

    pub fn fromProgramReader(prog_reader: *std.Io.Reader) !Self {
        var machine: Self = .fresh;
        var mem_writer: std.Io.Writer = .fixed(&machine.memory);
        machine.prog_len = try prog_reader.streamRemaining(&mem_writer);

        return machine;
    }

    pub fn simulate(self: *Self) !void {
        self.pc = 0x00000000;

        while (self.nextInstruction()) |instruction| {
            self.handle(instruction) catch |err| {
                std.process.fatal("handling 0x{X:0>8}: {s}", .{ self.fetchWordUnsigned(self.pc), @errorName(err) });
            };
            if (instruction != .btype) self.pc += 4;
        }
    }

    fn handle(self: *Self, instr: Instruction) !void {
        switch (instr) {
            .rtype => |r| switch (r.cmd) {
                .add => self.writeRegister(r.rd, self.readRegister(r.rs1) + self.readRegister(r.rs2)),
                .sub => self.writeRegister(r.rd, self.readRegister(r.rs1) - self.readRegister(r.rs2)),
                .@"or" => self.writeRegister(r.rd, self.readRegister(r.rs1) | self.readRegister(r.rs2)),
                .@"and" => self.writeRegister(r.rd, self.readRegister(r.rs1) & self.readRegister(r.rs2)),
                .slt => self.writeRegister(r.rd, if (self.readRegister(r.rs1) < self.readRegister(r.rs2)) 1 else 0),
                else => unreachable,
            },
            .itype => |i| switch (i.cmd) {
                .lw => {
                    const addr = self.readRegister(i.rs1) + i.imm12;
                    if (addr < 0) return error.InvalidAddress;
                    self.writeRegister(i.rd, self.fetchWord(@intCast(addr)));
                },
                .addi => self.writeRegister(i.rd, self.readRegister(i.rs1) + i.imm12),
                else => unreachable,
            },
            .stype => |s| {
                const addr = self.readRegister(s.rs1) + s.offset;
                if (addr < 0) return error.InvalidAddr;
                const word = self.readRegister(s.rs2);
                try self.storeWord(word, @intCast(addr));
            },
            .btype => |b| {
                if (self.readRegister(b.rs1) == self.readRegister(b.rs2)) {
                    if (@mod(b.offset, 4) != 0) return error.InvalidBranchOffset;
                    if (b.offset < 0) {
                        self.pc -= @intCast(-b.offset);
                    } else self.pc += @intCast(b.offset);
                } else self.pc += 4;
            },
        }
    }

    fn readRegister(self: *Self, reg: u5) i32 {
        return self.register_bank[reg];
    }

    fn writeRegister(self: *Self, rd: u5, word: i32) void {
        if (rd == 0) return;
        self.register_bank[rd] = word;
    }

    fn storeWord(self: *Self, word: i32, addr: u32) !void {
        if (addr <= self.prog_len) return error.InstructionOverwrite;
        if (addr >= self.memory.len - 3) return error.InvalidAddress;
        var bytes: [4]u8 = undefined;
        std.mem.writeInt(i32, &bytes, word, .little);
        @memcpy(self.memory[addr .. addr + 4], &bytes);
    }

    fn fetchWordUnsigned(self: *Self, addr: usize) u32 {
        return @bitCast(self.fetchWord(addr));
    }

    fn fetchWord(self: *Self, addr: usize) i32 {
        return std.mem.readInt(i32, self.memory[addr..][0..4], .little);
    }

    fn nextInstruction(self: *Self) ?Instruction {
        if (self.pc == self.prog_len) return null;
        const raw_instruction: u32 = @bitCast(self.fetchWord(self.pc));
        return parseInstruction(raw_instruction);
    }

    fn parseInstruction(raw: u32) Instruction {
        const raw_machine: MachineInstruction = .{ .raw = raw };
        switch (raw_machine.with_op.op) {
            51 => return .{
                .rtype = .{
                    .cmd = switch (raw_machine.rtype.funct3) {
                        0 => switch (raw_machine.rtype.funct7) {
                            0 => .add,
                            32 => .sub,
                            else => unreachable,
                        },
                        2 => .slt,
                        6 => .@"or",
                        7 => .@"and",
                        else => unreachable,
                    },
                    .rd = raw_machine.rtype.rd,
                    .rs1 = raw_machine.rtype.rs1,
                    .rs2 = raw_machine.rtype.rs2,
                },
            },
            3, 19 => |op| return .{
                .itype = .{
                    .cmd = switch (op) {
                        3 => .lw,
                        19 => .addi,
                        else => unreachable,
                    },
                    .rd = raw_machine.itype.rd,
                    .rs1 = raw_machine.itype.rs1,
                    .imm12 = @bitCast(raw_machine.itype.imm12),
                },
            },
            35 => {
                const offset_upper_7: i12 = @as(i12, @intCast(raw_machine.stype.imm7)) << 5;
                return .{
                    .stype = .{
                        .cmd = .sw,
                        .rs1 = raw_machine.stype.rs1,
                        .rs2 = raw_machine.stype.rs2,
                        .offset = offset_upper_7 + @as(u5, @bitCast(raw_machine.stype.imm5)),
                    },
                };
            },
            99 => {
                const Upper = packed struct(u7) { @"10:5": u6, sign: u1 };
                const Lower = packed struct(u5) { @"11": u1, @"4:1": u4 };
                const upper: Upper = @bitCast(raw_machine.btype.imm7);
                const lower: Lower = @bitCast(raw_machine.btype.imm5);
                var offset_unsigned: u13 = upper.sign;
                offset_unsigned = offset_unsigned << 1;
                offset_unsigned += lower.@"11";
                offset_unsigned = offset_unsigned << 6;
                offset_unsigned += upper.@"10:5";
                offset_unsigned = offset_unsigned << 4;
                offset_unsigned += lower.@"4:1";
                offset_unsigned = offset_unsigned << 1;
                return .{
                    .btype = .{
                        .cmd = .beq,
                        .rs1 = raw_machine.stype.rs1,
                        .rs2 = raw_machine.stype.rs2,
                        .offset = @bitCast(offset_unsigned),
                    },
                };
            },
            else => |op| std.process.fatal("unhandled op: {}", .{op}),
        }
    }
};
