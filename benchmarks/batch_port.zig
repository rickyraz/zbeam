//! Matched bounded ETF/raw batch controls, optional developer executable.
const std = @import("std");
const z = @import("zbeam");
pub fn raw(bytes: []const u8, output: *[1024]u8) ![]const u8 {
    if (bytes.len < 4) return error.Truncated;
    const count = std.mem.readInt(u32, bytes[0..4], .big);
    if (count == 0 or count > 32) return error.InvalidBatch;
    var offset: usize = 4;
    var total: usize = 0;
    for (0..count) |i| {
        if (bytes.len - offset < 4) return error.Truncated;
        const length = std.mem.readInt(u32, bytes[offset..][0..4], .big);
        offset += 4;
        if (length > 1024 * 1024 - total) return error.BatchTooLarge;
        if (length > bytes.len - offset) return error.Truncated;
        std.crypto.hash.sha2.Sha256.hash(bytes[offset..][0..length], output[i * 32 ..][0..32], .{});
        offset += length;
        total += length;
    }
    if (offset != bytes.len) return error.TrailingBytes;
    return output[0 .. count * 32];
}
pub fn main(init: std.process.Init) !void {
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();
    _ = args.next();
    const mode = args.next() orelse return error.MissingMode;
    const is_raw = std.mem.eql(u8, mode, "raw");
    if (!is_raw and !std.mem.eql(u8, mode, "etf")) return error.InvalidMode;
    if (args.next() != null) return error.UnexpectedArgument;
    var in_buffer: [4096]u8 = undefined;
    var out_buffer: [4096]u8 = undefined;
    var input = std.Io.File.Reader.initStreaming(.stdin(), init.io, &in_buffer);
    var output = std.Io.File.Writer.initStreaming(.stdout(), init.io, &out_buffer);
    const bytes = try init.gpa.alloc(u8, 2 * 1024 * 1024);
    defer init.gpa.free(bytes);
    var handler: z.runtime.BatchSha256 = .{};
    while (true) {
        var header: [4]u8 = undefined;
        const n = try input.interface.readSliceShort(&header);
        if (n == 0) return;
        if (n != 4) return error.Truncated;
        const size = std.mem.readInt(u32, &header, .big);
        if (size > bytes.len) return error.PacketTooLarge;
        try input.interface.readSliceAll(bytes[0..size]);
        var digests: [1024]u8 = undefined;
        const reply = if (is_raw) try raw(bytes[0..size], &digests) else block: {
            var request = try z.etf.decode(init.gpa, bytes[0..size], .{ .max_collection_len = 32, .max_binary_bytes = 1024 * 1024, .max_allocated_bytes = 2 * 1024 * 1024 });
            defer request.deinit(init.gpa);
            var response = try handler.compute(init.gpa, &request);
            defer response.deinit(init.gpa);
            break :block try z.etf.encode(init.gpa, &response);
        };
        defer if (!is_raw) init.gpa.free(reply);
        std.mem.writeInt(u32, &header, @intCast(reply.len), .big);
        try output.interface.writeAll(&header);
        try output.interface.writeAll(reply);
        try output.interface.flush();
    }
}
test "raw batch validates independent digests and malformed framing" {
    var output: [1024]u8 = undefined;
    const bytes = &[_]u8{ 0, 0, 0, 2, 0, 0, 0, 3, 'a', 'b', 'c', 0, 0, 0, 0 };
    const actual = try raw(bytes, &output);
    var expected: [64]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash("abc", expected[0..32], .{});
    std.crypto.hash.sha2.Sha256.hash("", expected[32..64], .{});
    try std.testing.expectEqualSlices(u8, &expected, actual);
    try std.testing.expectError(error.InvalidBatch, raw(&.{ 0, 0, 0, 33 }, &output));
    try std.testing.expectError(error.Truncated, raw(bytes[0..12], &output));
    try std.testing.expectError(error.BatchTooLarge, raw(&.{ 0, 0, 0, 1, 0, 16, 0, 1 }, &output));
    try std.testing.expectError(error.TrailingBytes, raw(&.{ 0, 0, 0, 1, 0, 0, 0, 0, 1 }, &output));
}
