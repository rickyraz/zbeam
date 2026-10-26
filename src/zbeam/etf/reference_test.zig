const std = @import("std");
const etf = @import("codec.zig");

pub const canonical = [_]u8{ 131, 90, 0, 3, 119, 3, 'n', '@', 'h', 0, 0, 0, 7, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 3 };

fn roundTrip(allocator: std.mem.Allocator, bytes: []const u8) !void {
    var term = try etf.decode(allocator, bytes, .{});
    defer term.deinit(allocator);
    const encoded = try etf.encode(allocator, &term);
    defer allocator.free(encoded);
    try std.testing.expectEqualSlices(u8, bytes, encoded);
}

test "reference canonical roundtrip and allocation failure cleanup" {
    try roundTrip(std.testing.allocator, &canonical);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, roundTrip, .{&canonical});
    for (0..canonical.len) |cut| try std.testing.expectError(error.Truncated, etf.decode(std.testing.allocator, canonical[0..cut], .{}));
    try std.testing.expectError(error.LimitExceeded, etf.decode(std.testing.allocator, &canonical, .{ .max_allocated_bytes = 2 }));
}

test "reference bounds fail before allocating node names" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    for ([_]u8{ 0, 6, 255 }) |len| {
        try std.testing.expectError(error.InvalidReference, etf.decode(failing.allocator(), &.{ 131, 90, 0, len }, .{}));
    }
    try std.testing.expect(!failing.has_induced_failure);
    try std.testing.expectError(error.InvalidAtom, etf.decode(std.testing.allocator, &.{ 131, 90, 0, 1, 97, 0 }, .{}));
    var ref = etf.Reference{ .node = "n@h", .creation = 1, .len = 5, .ids = .{ 1, 2, 3, 4, 0xffffffff } };
    const bytes = try etf.encode(std.testing.allocator, &.{ .reference = ref });
    defer std.testing.allocator.free(bytes);
    try roundTrip(std.testing.allocator, bytes);
    ref.len = 6;
    try std.testing.expectError(error.InvalidReference, etf.encode(std.testing.allocator, &.{ .reference = ref }));
}

test "legacy reference validates significant bits and canonicalizes to newer" {
    const legacy = [_]u8{ 131, 114, 0, 1, 119, 1, 'n', 3, 0, 3, 255, 255 };
    var term = try etf.decode(std.testing.allocator, &legacy, .{});
    defer term.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u32, 0x3ffff), term.reference.ids[0]);
    const bytes = try etf.encode(std.testing.allocator, &term);
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqual(@as(u8, 90), bytes[1]);
    var bad = legacy;
    bad[7] = 4;
    try std.testing.expectError(error.InvalidReference, etf.decode(std.testing.allocator, &bad, .{}));
    bad = legacy;
    bad[9] = 4;
    try std.testing.expectError(error.InvalidReference, etf.decode(std.testing.allocator, &bad, .{}));
}

test "PID and reference equality compares values rather than backing pointers" {
    const a = etf.Reference{ .node = "n@h", .creation = 7, .len = 3, .ids = .{ 1, 2, 3, 0, 0 } };
    var b = a;
    var node = "n@h".*;
    b.node = &node;
    try std.testing.expect(a.eql(b));
    b.ids[2] += 1;
    try std.testing.expect(!a.eql(b));
    const pid = etf.Pid{ .node = "n@h", .creation = 7, .id = 1, .serial = 2 };
    var other = pid;
    other.node = &node;
    try std.testing.expect(pid.eql(other));
    other.creation += 1;
    try std.testing.expect(!pid.eql(other));
}
