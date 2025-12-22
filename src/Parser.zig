const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const functools = @import("functools");

const root = @import("root.zig");
const Token = root.Token;
const Ast = root.Ast;

const Parser = @This();

// State required: Errors, TokenStream, Ast, Scratch data?
alloc: Allocator,
arena: ArenaAllocator,
ts: []Token,

/// Stack containing SourceLocations, so we can just return specific types
/// without Node bollocks.
toklocs: std.ArrayList(Ast.SourceLoc),

/// The source code of the program.
source: [:0]const u8,
filename: [:0]const u8,

/// Stored pointer to free the `ts`. Consuming a Token is little more than
/// updating start pointer.
initial_ptr: [*]Token,
initial_ts_len: usize,

newline_locs: []usize,

ast: Ast,

/// Deinitialise with `deinit`. `ts` is a slice but needn't outlive this parser.
pub fn init(
    alloc: Allocator,
    arena: ArenaAllocator,
    ts: []Token,
    source: [:0]const u8,
) Allocator.Error!Parser {
    const arena_alloc = arena.allocator();
    const filtered_ts = try functools.filter(arena_alloc, is_comment, ts);

    const newline_locs = try compute_newline_locs(arena_alloc, source);
    const toklocs = try std.ArrayList(Ast.SourceLoc).initCapacity(
        arena_alloc,
        5,
    );

    return Parser{
        .alloc = alloc,
        .arena = arena,
        .ts = filtered_ts,
        .initial_ptr = filtered_ts.ptr,
        .initial_ts_len = filtered_ts.len,
        .source = source,
        .newline_locs = newline_locs,
        .filename = "TODO.c",
        .toklocs = toklocs,
        .ast = Ast{
            .tokens = ts,
            .errors = undefined,
            // Node list.
            .nodes = std.ArrayList(Ast.Node).empty,
            .source = source,
        },
    };
}

pub fn parse(self: *Parser) !Ast {
    // TODO: Do some stuff.
    return self.ast;
}

/// Push a node to the node list and return it's index.
pub fn push_node(self: *Parser, node: Ast.Node) !usize {
    try self.ast.nodes.append(self.alloc, node);
    return self.ast.nodes.items.len - 1;
}

pub fn peek(self: *Parser) ?Token {
    if (self.ts.len == 0) return null;

    return self.ts[1];
}

/// Pop the last token location from the stack.
pub fn pop_tokloc(self: *Parser) ?Ast.SourceLoc {
    return self.toklocs.pop();
}

pub fn swallow_token(self: *Parser, expected_tag: Token.TokenType) !Token {
    const tok = self.ts[0];

    try self.toklocs.append(
        self.arena.allocator(),
        self.compute_source_loc(tok),
    );

    self.ts = self.ts[1..];

    if (expected_tag != tok.tag) {
        return error.UnexpectedToken; // TODO: Make this a proper error set.
    }

    return tok;
}

pub fn get_token_text(self: *Parser, tok: Token) []const u8 {
    return self.source[tok.loc.start..tok.loc.end];
}

pub fn parse_int_literal(self: *Parser) !Ast.IntLiteral {
    const tok = try self.swallow_token(.numeric_literal);
    const text = self.get_token_text(tok);
    const int = try std.fmt.parseInt(usize, text, 10);

    const node = Ast.IntLiteral{ .value = int };
    return node;
}

/// Caller must free returned slice.
pub fn compute_newline_locs(arena: Allocator, source: [:0]const u8) ![]usize {
    var out = try std.ArrayList(usize).initCapacity(arena, source.len / 8);
    defer out.deinit(arena);

    for (source, 0..) |b, idx| {
        // TODO: Handle windows line-endings.
        if (b != '\n') continue;
        out.appendAssumeCapacity(idx);
    }

    return try out.toOwnedSlice(arena);
}

/// Computes the source location for a given `tok`.
pub fn compute_source_loc(self: *Parser, tok: Token) Ast.SourceLoc {
    for (self.newline_locs, 0..) |l, idx| {
        if (tok.loc.end <= l) {
            return Ast.SourceLoc{
                .file = self.filename,
                .line = idx + 1,
                .column = if (idx == 0)
                    tok.loc.start
                else
                    tok.loc.start - self.newline_locs[idx - 1],
            };
        }
    }

    unreachable;
}

pub fn parse_expr(self: *Parser) !Ast.Expr {
    const int_literal = try self.parse_int_literal();

    return Ast.Expr{
        .int_literal = int_literal,
    };
}

pub fn parse_return_stmt(self: *Parser) !Ast.ReturnStmt {
    _ = try self.swallow_token(.kw_return);

    return Ast.ReturnStmt{ .expr = self.parse_expr() catch null };
}

pub fn parse_block_stmt(self: *Parser) !Ast.BlockStmt {
    _ = try self.swallow_token(.open_brace);

    var stmts = std.ArrayList(Ast.Node).empty;

    while (self.peek()) |t| {
        if (t.tag == .close_brace) break;

        const got = self.parse_return_stmt() catch {
            break try self.parse_block_stmt();
        };

        try stmts.append(self.alloc, Ast.Node{
            .loc = undefined,
            .tag = got,
        });
    }

    _ = try self.swallow_token(.close_brace);

    return Ast.BlockStmt{ .stmts = stmts };
}

pub fn deinit(self: Parser) void {
    self.arena.deinit();
    // (&self.initial_ptr[0..self.initial_ts_len]);
    // self.arena.free(self.newline_locs);
}

fn is_comment(t: Token) bool {
    return t.tag == .line_comment;
}

fn tokenise_and_init_parser(alloc: Allocator, source: [:0]const u8) Allocator.Error!Parser {
    var tokeniser = root.Tokeniser.init(source);
    const tokens = try tokeniser.collectToEof(alloc);
    defer alloc.free(tokens);

    const arena = std.heap.ArenaAllocator.init(alloc);

    return try Parser.init(alloc, arena, tokens, source);
}

test "parse int literal" {
    const alloc = std.testing.allocator;
    const source = "67";

    var parser = try tokenise_and_init_parser(alloc, source);
    defer parser.deinit();

    _ = try parser.parse_int_literal();
}

test "parse expr -- simple int literal" {
    const alloc = std.testing.allocator;
    const source = "67;";

    var parser = try tokenise_and_init_parser(alloc, source);
    defer parser.deinit();

    _ = try parser.parse_int_literal();
}

test "fucking die" {
    @panic("woophs");
}
