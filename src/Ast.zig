const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const lib = @import("root.zig");
const Tokeniser = lib.Tokeniser;
const Token = Tokeniser.Token;

const Ast = @This();

const TokenList = std.ArrayList(Token);
const NodeList = std.ArrayList(Node);

/// Represents a source location for error reporting and debugging.
pub const SourceLoc = struct {
    /// Could be a file index or path; for now, a string slice.
    file: []const u8,
    line: u32,
    column: u32,
};

pub const Node = struct {
    loc: SourceLoc,
    tag: NodeTag,
};

pub const NodeTag = union(enum) {
    program: Program,
    fn_decl: FnDecl,
    block_stmt: BlockStmt,
    return_stmt: ReturnStmt,
    int_literal: IntLiteral,
};

/// Root program node: contains all top-level declarations.
pub const Program = struct {
    /// List of declarations (e.g., function declarations).
    decls: []const Node,
};

/// Function declaration node.
pub const FnDecl = struct {
    /// Stored as a string, could be an enum later.
    return_type: []const u8,
    /// Function name (e.g. "main").
    name: []const u8,
    params: []const Param,
    /// Body, as a block statement.
    body: *Node,
};

/// Parameter for functions (minimal for now).
pub const Param = struct {
    type: []const u8,
    name: []const u8,
};

/// Block statement node (e.g., { return 67; }).
pub const BlockStmt = struct {
    stmts: []const Node,
};

/// Return statement node.
pub const ReturnStmt = struct {
    /// Optional expression (null for void returns, but present here).
    expr: ?*Node,
};

/// Expression union for different expression types.
pub const Expr = union(enum) {
    int_literal: IntLiteral,
};

/// Integer literal expression.
pub const IntLiteral = struct {
    /// TODO: Check what C wants.
    value: i64,
};

/// Taken from the standard library, true if we want safety checks.
fn runtime_safety() bool {
    return switch (builtin.mode) {
        .ReleaseSafe, .Debug => true,
        .ReleaseFast, .ReleaseSmall => false,
    };
}

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
