//! Optional benchmark executable, never a runtime dependency.
const std = @import("std");
const etf = @import("zbeam-etf");
const maximum = 1024 * 1024;

pub fn transform(allocator: std.mem.Allocator, bytes: []const u8, hashing: bool) ![]u8 {
    var term = try etf.decode(allocator, bytes, .{ .max_binary_bytes = maximum, .max_allocated_bytes = 2 * maximum });
    defer term.deinit(allocator);
    if (term != .binary) return error.InvalidPayload;
    var digest: [32]u8 = undefined;
    if (hashing) std.crypto.hash.sha2.Sha256.hash(term.binary, &digest, .{});
    var result = etf.Term{ .binary = if (hashing) &digest else term.binary };
    return etf.encode(allocator, &result);
}

pub fn main(init: std.process.Init) !void {
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();
    _ = args.next();
    const job = args.next() orelse return error.MissingJob;
    const hashing = std.mem.eql(u8, job, "sha256");
    if (!hashing and !std.mem.eql(u8, job, "echo")) return error.InvalidJob;
    if (args.next() != null) return error.UnexpectedArgument;
    var in_buffer: [4096]u8 = undefined;
    var out_buffer: [4096]u8 = undefined;
    var input = std.Io.File.Reader.initStreaming(.stdin(), init.io, &in_buffer);
    var output = std.Io.File.Writer.initStreaming(.stdout(), init.io, &out_buffer);
    var bytes: [maximum + 6]u8 = undefined;
    while (true) {
        var header: [4]u8 = undefined;
        const n = try input.interface.readSliceShort(&header);
        if (n == 0) return;
        if (n != header.len) return error.Truncated;
        const length = std.mem.readInt(u32, &header, .big);
        if (length > bytes.len) return error.PacketTooLarge;
        try input.interface.readSliceAll(bytes[0..length]);
        const response = try transform(init.gpa, bytes[0..length], hashing);
        defer init.gpa.free(response);
        std.mem.writeInt(u32, &header, @intCast(response.len), .big);
        try output.interface.writeAll(&header);
        try output.interface.writeAll(response);
        try output.interface.flush();
    }
}

test "ETF Port checks exact echo/hash, malformed input and allocation cleanup" {
    const a = std.testing.allocator;
    var input = etf.Term{ .binary = "abc" };
    const encoded = try etf.encode(a, &input);
    defer a.free(encoded);
    for ([_]bool{ false, true }) |hashing| {
        const output = try transform(a, encoded, hashing);
        defer a.free(output);
        var decoded = try etf.decode(a, output, .{});
        defer decoded.deinit(a);
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash("abc", &digest, .{});
        try std.testing.expectEqualSlices(u8, if (hashing) &digest else "abc", decoded.binary);
    }
    try std.testing.expectError(error.InvalidPayload, transform(a, &.{ 131, 97, 1 }, false));
    try std.testing.expectError(error.Truncated, transform(a, &.{ 131, 109 }, false));
    try std.testing.expectError(error.LimitExceeded, transform(a, &.{ 131, 109, 0, 16, 0, 1 }, false));
    try std.testing.checkAllAllocationFailures(a, allocationCase, .{});
}

fn allocationCase(a: std.mem.Allocator) !void {
    const response = try transform(a, &.{ 131, 109, 0, 0, 0, 3, 'a', 'b', 'c' }, true);
    a.free(response);
}
