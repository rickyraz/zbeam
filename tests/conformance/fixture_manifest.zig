const std = @import("std");

const manifest = @import("zbeam-etf-fixtures").bytes;

test "ETF fixture manifest has bounded versioned vectors" {
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
        vectors += 1;
    }

    try std.testing.expectEqual(@as(usize, 7), vectors);
}
