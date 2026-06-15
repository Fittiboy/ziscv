const std = @import("std");
const meta = std.meta;
const testing = std.testing;
const Io = std.Io;

const Self = @This();

const whitespace = " \r\t";
const special = " \r\t\n,:-()";

buffer: []const u8,
pos: usize,
line: u32,
col: u32,
done: bool = false,
next_token: ?Token = null,

pub const Token = union(enum) {
    eof,
    newline,
    name: []const u8,
    number: i32,
    comma,
    colon,
    minus,
    l_paren,
    r_paren,

    pub fn fromChar(c: u8) Token {
        const char_token: CharToken = @enumFromInt(c);
        return switch (char_token) {
            .comma => .comma,
            .colon => .colon,
            .minus => .minus,
            .l_paren => .l_paren,
            .r_paren => .r_paren,
        };
    }

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        switch (self) {
            .eof, .newline, .comma, .colon, .minus, .l_paren, .r_paren => {
                try writer.print("{s}", .{@tagName(self)});
            },
            .name => |str| try writer.print("name(\"{s}\")", .{str}),
            .number => |n| try writer.print("number({d})", .{n}),
        }
    }
};

const CharToken = enum(u8) {
    comma = ',',
    colon = ':',
    minus = '-',
    l_paren = '(',
    r_paren = ')',
};

pub fn init(buffer: []const u8) Self {
    return .{
        .buffer = buffer,
        .pos = 0,
        .line = 0,
        .col = 0,
    };
}

fn peek(self: Self) ?u8 {
    if (self.pos >= self.buffer.len) return null;
    return self.buffer[self.pos];
}

fn toss(self: *Self) void {
    self.pos += 1;
    self.col += 1;
}

/// This can be called after ensuring we have not hit EOF
/// by calling `peek` first.
fn consumeNoEof(self: *Self) u8 {
    defer self.toss();
    return self.buffer[self.pos];
}

fn isWhitespace(c: u8) bool {
    for (whitespace) |w| if (w == c) return true;
    return false;
}

fn isSpecial(c: u8) bool {
    for (special) |w| if (w == c) return true;
    return false;
}

pub fn peekToken(self: *Self) !?Token {
    if (self.next_token) |tok| return tok;
    self.next_token = try self.next();
    return self.next_token;
}

pub fn next(self: *Self) !?Token {
    if (self.done) return null;
    const token = try self.nextInternal();
    if (token == .eof) self.done = true;
    return token;
}

fn nextInternal(self: *Self) !Token {
    if (self.next_token) |tok| {
        self.next_token = null;
        return tok;
    }

    var c = self.peek() orelse return .eof;

    // Discard whitespace
    while (isWhitespace(c)) {
        self.toss();
        c = self.peek() orelse return .eof;
    }

    // Discard comments
    if (c == '#') while (c != '\n') {
        self.toss();
        c = self.peek() orelse return .eof;
    };

    switch (c) {
        '\n' => {
            self.toss();
            self.line += 1;
            self.col = 0;
            return .newline;
        },
        ',', ':', '-', '(', ')' => return self.lexChar(),
        '0'...'9' => return try self.lexNumber(),
        'a'...'z', 'A'...'Z', '_' => return try self.lexName(),
        else => return error.IllegalCharacter,
    }
}

/// Calling this function when the next character is not
/// one of ",:-()" invokes safety-checked illegal behavior.
fn lexChar(self: *Self) Token {
    return Token.fromChar(self.consumeNoEof());
}

fn lexNumber(self: *Self) !Token {
    const slice = self.nameOrNumber();
    return .{ .number = std.fmt.parseInt(i32, slice, 0) catch {
        return error.IllegalCharacterInNumber;
    } };
}

fn lexName(self: *Self) !Token {
    const slice = self.nameOrNumber();
    for (slice) |c| {
        switch (c) {
            'a'...'z', 'A'...'Z', '0'...'9', '_' => continue,
            else => return error.IllegalCharacterInName,
        }
    } else return .{ .name = slice };
}

fn nameOrNumber(self: *Self) []const u8 {
    const start = self.pos;
    var c = self.peek().?;
    while (!isSpecial(c)) {
        self.toss();
        c = self.peek() orelse break;
    }

    return self.buffer[start..self.pos];
}

//
//
//
// TESTS
//
//
//

test "small Tokenizer smoke test" {
    const buffer =
        \\add rp, hero, twelve, 12, -1(hello) # With a comment, too!
        \\   #This one just has a comment!! :)))
        \\and_a_label_here0:,
    ;

    const expected = [_]Token{
        .{ .name = "add" },
        .{ .name = "rp" },
        .comma,
        .{ .name = "hero" },
        .comma,
        .{ .name = "twelve" },
        .comma,
        .{ .number = 12 },
        .comma,
        .minus,
        .{ .number = 1 },
        .l_paren,
        .{ .name = "hello" },
        .r_paren,
        .newline,
        .newline,
        .{ .name = "and_a_label_here0" },
        .colon,
        .comma,
        .eof,
    };

    var tokenizer: Self = .init(buffer);
    var i: usize = 0;
    while (try tokenizer.next()) |tok| : (i += 1) {
        try testing.expectEqualDeep(expected[i], tok);
    }
}

test "Tokenizer error on illegal character in general" {
    const buffer = "add !, x1, x2";
    var tokenizer: Self = .init(buffer);
    _ = try tokenizer.next();
    try std.testing.expectError(error.IllegalCharacter, tokenizer.next());
}

test "Tokenizer error on illegal character in name" {
    const buffer = "add hello&there, x1, x2";
    var tokenizer: Self = .init(buffer);
    _ = try tokenizer.next();
    try std.testing.expectError(error.IllegalCharacterInName, tokenizer.next());
}

test "Tokenizer error on non-numeric string that starts with digit" {
    const buffer = "add 0x, x1, x2";
    var tokenizer: Self = .init(buffer);
    _ = try tokenizer.next();
    try std.testing.expectError(error.IllegalCharacterInNumber, tokenizer.next());
}
