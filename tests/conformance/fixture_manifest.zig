const std = @import("std");
const etf = @import("zbeam-etf");

const manifest = @import("zbeam-etf-fixtures").bytes;

test "ETF fixture manifest has bounded versioned vectors" {
    // Parse the checked-in text rather than embedding duplicate expected terms.
    // The first octet must be 0x83 (decimal 131), ETF's version marker; decoding
    // and re-encoding then proves these canonical vectors preserve exact bytes.
    // Other valid representations may canonicalize; for example, a byte-valued
    // LIST_EXT is encoded as STRING_EXT by the ETF encoder.
    var lines = std.mem.splitScalar(u8, manifest, '\n');
    var vectors: usize = 0;

    while (lines.next()) |line| {
        if (line.len == 0 or line[0] == '#') continue;

        var columns = std.mem.splitScalar(u8, line, '\t');
        const name = columns.next() orelse return error.InvalidFixture;
        const expression = columns.next() orelse return error.InvalidFixture;
        const hex = columns.next() orelse return error.InvalidFixture;

        try std.testing.expect(columns.next() == null);
        try std.testing.expect(name.len > 0);
        try std.testing.expect(expression.len > 0);
        try std.testing.expect(hex.len >= 4 and hex.len % 2 == 0);
        try std.testing.expectEqualStrings("83", hex[0..2]);

        var buffer: [1024]u8 = undefined;
        const bytes = try std.fmt.hexToBytes(&buffer, hex);
        var term = try etf.decode(std.testing.allocator, bytes, .{});
        defer term.deinit(std.testing.allocator);
        const encoded = try etf.encode(std.testing.allocator, &term);
        defer std.testing.allocator.free(encoded);
        try std.testing.expectEqualSlices(u8, bytes, encoded);
        vectors += 1;
    }

    try std.testing.expectEqual(@as(usize, 7), vectors);
}
