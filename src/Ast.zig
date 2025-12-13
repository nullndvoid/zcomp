const std = @import("std");
const Allocator = std.mem.Allocator;

const lib = @import("root.zig");
const Tokeniser = lib.Tokeniser;
const Token = Tokeniser.Token;

const Ast = @This();

// https://codeberg.org/ziglang/zig/src/commit/2da956b84a1f26ea9b52e2314e8393cffba95df2/lib/std/zig/Ast.zig

// pub const TokenIdx = u32;

const TokenList = std.ArrayList(Token);
const NodeList = std.ArrayList(Node);

pub const Node = struct { id: usize };

source: [:0]const u8,
tokens: TokenList,
nodes: NodeList,
errors: []const Error,
// extra_data: []u32,

pub fn parse(alloc: Allocator, source: [:0]const u8) Allocator.Error!Ast {
    // Tokenise the source.
    var tokeniser = Tokeniser.init(source);
    var tokens = TokenList.empty;
    defer tokens.deinit(alloc);

    while (true) {
        const tok = tokeniser.next();
        try tokens.append(alloc, tok);

        if (tok.tag == .eof) break;
    }

    for (tokens.items) |tok| {
        tokeniser.dump(&tok);
    }

    return Ast{
        .errors = undefined,
        .nodes = undefined,
        .source = undefined,
        .tokens = undefined,
    };
}

pub const Error = struct {};
