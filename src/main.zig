const std = @import("std");
const zcomp = @import("zcomp");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    // Read in a file path from args.
    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    if (args.len < 2)
        return error.NoSourcePath;

    const file_path = args[1];

    var buf: [4096]u8 = undefined;
    const file = try std.fs.cwd().openFile(file_path, .{});
    var rdr = file.reader(&buf);
    const file_stat = try file.stat();

    const bytes = try rdr.interface.readAlloc(alloc, file_stat.size);
    const bytes_sentinel = try alloc.dupeZ(u8, bytes);

    defer alloc.free(bytes_sentinel);
    alloc.free(bytes);

    _ = try zcomp.Ast.parse(alloc, bytes_sentinel);
}
