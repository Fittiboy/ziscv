const std = @import("std");
const Io = std.Io;

const Self = @This();

const whitespace = " \r\t";
const newline = '\n';
const pound = '#';

buffer: []const u8,
pos: usize,

pub const Token = union(enum) {
    const Loc = struct {
        start: usize,
        end: usize,
    };

    eof: void,
    newline: void,
    name: Loc,
    number: u32,
    comma,
    colon,
    minus,
    left_paren,
    right_paren,
};

pub fn init(buffer: []const u8) Self {
    return .{
        .buffer = buffer,
        .pos = 0,
    };
}

pub fn next() Token {
    return .eof;
}
