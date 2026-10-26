const std = @import("std");
const framing = @import("zbeam-transport").distribution_io;
const Reader = @import("lab-reader");

test "lab08: short-read matrix preserves frames without read-ahead" {
    const wire = [_]u8{ 0, 0, 0, 3, 112, 131, 106, 0, 0, 0, 0 };
    for (1..wire.len + 1) |chunk| {
        var source = Reader{ .bytes = &wire, .chunk = chunk };
        var tracked = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        const packet = try framing.readPacket(tracked.allocator(), &source.interface, 3);
        try std.testing.expectEqualSlices(u8, wire[0..7], packet);
        try std.testing.expectEqualSlices(u8, wire[7..], source.bytes);
        tracked.allocator().free(packet);
        try std.testing.expectEqual(@as(usize, 1), tracked.allocations);
        try std.testing.expectEqual(@as(usize, 7), tracked.allocated_bytes);
        try std.testing.expectEqual(tracked.allocated_bytes, tracked.freed_bytes);
        std.debug.print("lab08 chunk={d} reader_calls={d} allocations=1 allocated_bytes=7 unread_bytes=4\n", .{ chunk, source.read_calls });
    }
}

test "lab08: size rejection precedes allocation and OOM does not read payload" {
    const wire = [_]u8{ 0, 0, 0, 3, 112, 131, 106 };
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var oversized = Reader{ .bytes = &wire };
    try std.testing.expectError(error.PacketTooLarge, framing.readPacket(failing.allocator(), &oversized.interface, 2));
    try std.testing.expect(!failing.has_induced_failure);
    try std.testing.expectEqual(@as(usize, 4), oversized.consumed);
    var bounded = Reader{ .bytes = &wire };
    try std.testing.expectError(error.OutOfMemory, framing.readPacket(failing.allocator(), &bounded.interface, 3));
    try std.testing.expect(failing.has_induced_failure);
    try std.testing.expectEqual(@as(usize, 4), bounded.consumed);
}
