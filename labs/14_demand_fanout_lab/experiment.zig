const std = @import("std");

fn broadcastCredit(credits: []const u32) u32 {
    if (credits.len == 0) return 0;
    var minimum = credits[0];
    for (credits) |credit| minimum = @min(minimum, credit);
    return minimum;
}

fn broadcast(credits: []u32) bool {
    if (broadcastCredit(credits) == 0) return false;
    for (credits) |*credit| credit.* -= 1;
    return true;
}

fn partition(credits: []u32, cursor: *usize) ?usize {
    for (0..credits.len) |offset| {
        const index = (cursor.* + offset) % credits.len;
        if (credits[index] == 0) continue;
        credits[index] -= 1;
        cursor.* = (index + 1) % credits.len;
        return index;
    }
    return null;
}

test "lab14: broadcast waits for every required consumer without partial spending" {
    var credits = [_]u32{ 2, 1, 0 };
    try std.testing.expect(!broadcast(&credits));
    try std.testing.expectEqualSlices(u32, &.{ 2, 1, 0 }, &credits);
    credits[2] = 2;
    try std.testing.expectEqual(@as(u32, 1), broadcastCredit(&credits));
    try std.testing.expect(broadcast(&credits));
    try std.testing.expect(!broadcast(&credits));
    try std.testing.expectEqualSlices(u32, &.{ 1, 0, 1 }, &credits);
    try std.testing.expect(!broadcast(&.{}));
}

test "lab14: round-robin partition conserves credit and skips paused consumers" {
    var balanced = [_]u32{ 4, 4, 4 };
    var cursor: usize = 0;
    for (0..12) |sequence| try std.testing.expectEqual(sequence % 3, partition(&balanced, &cursor).?);
    try std.testing.expect(partition(&balanced, &cursor) == null);
    var skewed = [_]u32{ 4, 1, 0 };
    cursor = 0;
    for ([_]usize{ 0, 1, 0, 0, 0 }) |expected| try std.testing.expectEqual(expected, partition(&skewed, &cursor).?);
    try std.testing.expectEqualSlices(u32, &.{ 0, 0, 0 }, &skewed);
    try std.testing.expect(partition(&skewed, &cursor) == null);
    try std.testing.expect(partition(&.{}, &cursor) == null);
    std.debug.print("lab14 balanced_deliveries=4,4,4 skewed_deliveries=4,1,0 residual_credit=0\n", .{});
}

test "lab14: sum credit cannot authorize an unknown fixed destination" {
    var credits = [_]u32{ 0, 4 };
    try std.testing.expectEqual(@as(u32, 4), credits[0] + credits[1]);
    try std.testing.expectEqual(@as(u32, 0), broadcastCredit(&credits));
    var cursor: usize = 0;
    try std.testing.expectEqual(@as(usize, 1), partition(&credits, &cursor).?);
}
