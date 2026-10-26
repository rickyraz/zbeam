const std = @import("std");
const Bin = struct { bytes: usize, count: usize };
const Estimate = struct { pool_bytes: usize, fitting_frames: usize = 0, fallback_bytes: usize = 0, cumulative_padding: usize = 0 };

fn estimate(bins: []const Bin, slots: usize, size: usize) !Estimate {
    if (slots == 0 or size == 0) return error.InvalidPool;
    var result = Estimate{ .pool_bytes = try std.math.mul(usize, slots, size) };
    for (bins) |bin| {
        if (bin.bytes <= size) {
            result.fitting_frames = try std.math.add(usize, result.fitting_frames, bin.count);
            result.cumulative_padding = try std.math.add(usize, result.cumulative_padding, try std.math.mul(usize, size - bin.bytes, bin.count));
        } else {
            result.fallback_bytes = try std.math.add(usize, result.fallback_bytes, try std.math.mul(usize, bin.bytes, bin.count));
        }
    }
    return result;
}

test "lab15: synthetic size histogram exposes reservation versus fit trade-off" {
    const bins = [_]Bin{
        .{ .bytes = 32, .count = 80 },
        .{ .bytes = 256, .count = 15 },
        .{ .bytes = 4096, .count = 4 },
        .{ .bytes = 65536, .count = 1 },
    };
    const expected_fit = [_]usize{ 80, 95, 100 };
    const expected_fallback = [_]usize{ 85760, 81920, 0 };
    const expected_padding = [_]usize{ 2560, 90880, 6465280 };
    for ([_]usize{ 1, 4, 16 }) |slots| {
        for ([_]usize{ 64, 1024, 65536 }, 0..) |size, index| {
            const result = try estimate(&bins, slots, size);
            try std.testing.expectEqual(slots * size, result.pool_bytes);
            try std.testing.expectEqual(expected_fit[index], result.fitting_frames);
            try std.testing.expectEqual(expected_fallback[index], result.fallback_bytes);
            try std.testing.expectEqual(expected_padding[index], result.cumulative_padding);
            std.debug.print("lab15 slots={d} size={d} pool_bytes={d} fitting_frames={d}/100 fallback_bytes={d} cumulative_padding={d}\n", .{ slots, size, result.pool_bytes, result.fitting_frames, result.fallback_bytes, result.cumulative_padding });
        }
    }
}

test "lab15: exact fit, empty input, invalid pools and arithmetic overflow" {
    const exact = try estimate(&.{ .{ .bytes = 64, .count = 1 }, .{ .bytes = 65, .count = 1 } }, 1, 64);
    try std.testing.expectEqual(@as(usize, 1), exact.fitting_frames);
    try std.testing.expectEqual(@as(usize, 65), exact.fallback_bytes);
    try std.testing.expectEqual(@as(usize, 0), exact.cumulative_padding);
    try std.testing.expectEqual(@as(usize, 0), (try estimate(&.{}, 1, 64)).fitting_frames);
    try std.testing.expectError(error.InvalidPool, estimate(&.{}, 0, 64));
    try std.testing.expectError(error.InvalidPool, estimate(&.{}, 1, 0));
    try std.testing.expectError(error.Overflow, estimate(&.{}, std.math.maxInt(usize), 2));
    try std.testing.expectError(error.Overflow, estimate(&.{.{ .bytes = 2, .count = std.math.maxInt(usize) }}, 1, 1));
}
