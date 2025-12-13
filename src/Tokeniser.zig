//! The tokeniser code. Just a simple big state machine we can easily extend.
const std = @import("std");

pub const Token = struct {
    tag: TokenType,
    loc: Loc,

    /// Store our byte offsets in the file for quick lookup if required.
    pub const Loc = struct {
        start: usize,
        end: usize,
    };

    /// Token types to lex.
    pub const TokenType = enum {
        kw_int,
        ident,
        open_paren,
        close_paren,
        open_brace,
        close_brace,
        numeric_literal,
        kw_return,
        semicolon,
        eof,
        invalid,
        line_comment,

        pub fn lexeme(tag: TokenType) ?[]const u8 {
            return switch (tag) {
                .eof,
                .ident,
                .numeric_literal,
                .invalid,
                .line_comment,
                => null,
                .kw_int => "int",
                .kw_return => "return",
                .semicolon => ";",
                .open_paren => "(",
                .close_paren => ")",
                .open_brace => "{",
                .close_brace => "}",
            };
        }

        pub fn symbol(tag: TokenType) []const u8 {
            return tag.lexeme() orelse switch (tag) {
                .eof => "EOF",
                .numeric_literal => "a numeric literal",
                .ident => "an identifier",
                .invalid => "invalid token",
                .line_comment => "a line comment",
                // Expand when we expand above.
                else => unreachable,
            };
        }
    };

    /// A map of all the reserved words.
    pub const keywords = std.StaticStringMap(TokenType).initComptime(.{
        .{ "int", .kw_int },
        .{ "return", .kw_return },
    });

    pub fn getKeyword(bytes: []const u8) ?TokenType {
        return keywords.get(bytes);
    }
};

buffer: [:0]const u8,
index: usize,

const Tokeniser = @This();

/// Print out a Token for debugging purposes.
pub fn dump(self: *Tokeniser, token: *const Token) void {
    std.debug.print("{s} \"{s}\"\n", .{
        @tagName(token.tag),
        self.buffer[token.loc.start..token.loc.end],
    });
}

pub fn init(buffer: [:0]const u8) Tokeniser {
    return .{
        .buffer = buffer,
        // Skips the UTF-8 BOM if it's present. Stolen from Zig tokeniser code.
        .index = if (std.mem.startsWith(u8, buffer, "\xEF\xBB\xBF")) 3 else 0,
    };
}

const State = enum {
    start,
    invalid,
    int,
    ident,
    slash,
    line_comment,
};

pub fn next(self: *Tokeniser) Token {
    var res: Token = .{
        .tag = undefined,
        .loc = .{
            .start = self.index,
            .end = undefined,
        },
    };

    state: switch (State.start) {
        .start => switch (self.buffer[self.index]) {
            0 => {
                if (self.index == self.buffer.len) {
                    return .{
                        .tag = .eof,
                        .loc = .{
                            .start = self.index,
                            .end = self.index,
                        },
                    };
                } else {
                    continue :state .invalid;
                }
            },
            ' ', '\n', '\t', '\r' => {
                self.index += 1;
                res.loc.start = self.index;
                continue :state .start;
            },
            ';' => {
                res.tag = .semicolon;
                self.index += 1;
            },
            'a'...'z', 'A'...'Z', '_' => {
                res.tag = .ident;
                continue :state .ident;
            },
            '(' => {
                res.tag = .open_paren;
                self.index += 1;
            },
            ')' => {
                res.tag = .close_paren;
                self.index += 1;
            },
            '{' => {
                res.tag = .open_brace;
                self.index += 1;
            },
            '}' => {
                res.tag = .close_brace;
                self.index += 1;
            },
            '0'...'9' => {
                res.tag = .numeric_literal;
                self.index += 1;
                continue :state .int;
            },
            '/' => {
                self.index += 1;
                continue :state .slash;
            },
            else => {
                continue :state .invalid;
            },
        },
        .invalid => {
            self.index += 1;
            switch (self.buffer[self.index]) {
                0 => if (self.index == self.buffer.len) {
                    res.tag = .invalid;
                } else {
                    continue :state .invalid;
                },
                '\n' => res.tag = .invalid,
                else => continue :state .invalid,
            }
        },
        // Handles switching from identifier to keyword if detected.
        .ident => {
            self.index += 1;
            switch (self.buffer[self.index]) {
                'a'...'z', 'A'...'Z', '_', '0'...'9' => continue :state .ident,
                else => {
                    const ident = self.buffer[res.loc.start..self.index];
                    if (Token.getKeyword(ident)) |tag| {
                        res.tag = tag;
                    }
                },
            }
        },
        .int => switch (self.buffer[self.index]) {
            '0'...'9' => {
                self.index += 1;
                continue :state .int;
            },
            else => {},
        },
        .slash => switch (self.buffer[self.index]) {
            '/' => {
                self.index += 1;
                res.tag = .line_comment;
                continue :state .line_comment;
            },
            else => {
                continue :state .invalid;
            },
        },
        .line_comment => {
            self.index += 1;

            switch (self.buffer[self.index]) {
                '\n', 0 => {},
                else => continue :state .line_comment,
            }
        },
    }

    res.loc.end = self.index;
    return res;
}

test "skip BOM - lext test program" {
    const bom = "\xEF\xBB\xBF";
    const source =
        \\ int main() {
        \\      return 2;
        \\ }
    ;
    const source_with_bom = bom ++ source;

    var tokeniser = Tokeniser.init(source_with_bom);
    const alloc = std.testing.allocator;

    const expected_tags = &[_]Token.TokenType{
        .kw_int,
        .ident,
        .open_paren,
        .close_paren,
        .open_brace,
        .kw_return,
        .numeric_literal,
        .semicolon,
        .close_brace,
        .eof,
    };

    var toks = std.ArrayList(Token.TokenType).empty;
    defer toks.deinit(alloc);

    while (true) {
        const tok = tokeniser.next();
        try toks.append(alloc, tok.tag);

        if (tok.tag == .eof) break;
    }

    try std.testing.expectEqualSlices(Token.TokenType, expected_tags, toks.items);
}

test "lex test program" {
    const source =
        \\ int main() {
        \\      return 2;
        \\ }
    ;

    var tokeniser = Tokeniser.init(source);
    const alloc = std.testing.allocator;

    const expected_tags = &[_]Token.TokenType{
        .kw_int,
        .ident,
        .open_paren,
        .close_paren,
        .open_brace,
        .kw_return,
        .numeric_literal,
        .semicolon,
        .close_brace,
        .eof,
    };

    var toks = std.ArrayList(Token.TokenType).empty;
    defer toks.deinit(alloc);

    while (true) {
        const tok = tokeniser.next();
        try toks.append(alloc, tok.tag);

        if (tok.tag == .eof) break;
    }

    try std.testing.expectEqualSlices(Token.TokenType, expected_tags, toks.items);
}

test "tokenise invalid - early EOF" {
    const source = "\x00int main() { return 67; }";
    var tokeniser = Tokeniser.init(source);
    const alloc = std.testing.allocator;

    var toks = std.ArrayList(Token.TokenType).empty;
    defer toks.deinit(alloc);

    while (true) {
        const tok = tokeniser.next();
        try toks.append(alloc, tok.tag);
        if (tok.tag == .eof) break;
    }

    try std.testing.expectEqualSlices(Token.TokenType, &.{ .invalid, .eof }, toks.items);
}

// Handles comments and the simplest possible C function.
test "tokenise 01_int_main.c" {
    const alloc = std.testing.allocator;
    const file_path = "test/01_int_main.c";

    var buf: [4096]u8 = undefined;
    const file = try std.fs.cwd().openFile(file_path, .{});
    var rdr = file.reader(&buf);
    const file_stat = try file.stat();

    const bytes = try rdr.interface.readAlloc(alloc, file_stat.size);
    const bytes_sentinel = try alloc.dupeZ(u8, bytes);

    defer alloc.free(bytes_sentinel);
    alloc.free(bytes);

    var tokeniser = Tokeniser.init(bytes_sentinel);
    var toks = std.ArrayList(Token).empty;
    defer toks.deinit(alloc);

    const expected = &[_]Token{
        .{ .tag = .line_comment, .loc = .{ .start = 0, .end = 11 } },
        .{ .tag = .kw_int, .loc = .{ .start = 12, .end = 15 } },
        .{ .tag = .ident, .loc = .{ .start = 16, .end = 20 } },
        .{ .tag = .open_paren, .loc = .{ .start = 20, .end = 21 } },
        .{ .tag = .close_paren, .loc = .{ .start = 21, .end = 22 } },
        .{ .tag = .open_brace, .loc = .{ .start = 23, .end = 24 } },
        .{ .tag = .kw_return, .loc = .{ .start = 29, .end = 35 } },
        .{ .tag = .numeric_literal, .loc = .{ .start = 36, .end = 38 } },
        .{ .tag = .semicolon, .loc = .{ .start = 38, .end = 39 } },
        .{ .tag = .line_comment, .loc = .{ .start = 40, .end = 55 } },
        .{ .tag = .close_brace, .loc = .{ .start = 56, .end = 57 } },
        .{ .tag = .eof, .loc = .{ .start = 58, .end = 58 } },
    };

    while (true) {
        const tok = tokeniser.next();
        try toks.append(alloc, tok);
        if (tok.tag == .eof) break;
    }

    try std.testing.expectEqualSlices(Token, expected, toks.items);

    const first_comment_loc = toks.items[0].loc;
    try std.testing.expectEqualSlices(
        u8,
        "// Skip me.",
        bytes_sentinel[first_comment_loc.start..first_comment_loc.end],
    );
}
