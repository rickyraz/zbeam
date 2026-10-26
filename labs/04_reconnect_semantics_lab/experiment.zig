const std = @import("std");
const Demand = @import("zbeam-actor").Demand;
const read = @import("zbeam-transport").distribution_io.readDemandedPacket;
const Reader = @import("lab-reader");

test "lab04: every interrupted frame consumes old credit; fresh state reads a complete frame" {
    const wire = [_]u8{ 0, 0, 0, 3, 112, 131, 106 };
    for (0..wire.len) |cut| {
        var tracked = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        var old_source = Reader{ .bytes = wire[0..cut], .chunk = 1 };
        var old_demand = Demand.init(1);
        const expected_error = if (cut == 0) error.EndOfStream else error.Truncated;
        try std.testing.expectError(expected_error, read(tracked.allocator(), &old_source.interface, 32, &old_demand));
        try std.testing.expectEqual(@as(u32, 0), old_demand.load());
        try std.testing.expectEqual(tracked.allocated_bytes, tracked.freed_bytes);
        const calls = old_source.read_calls;
        try std.testing.expectError(error.NoDemand, read(tracked.allocator(), &old_source.interface, 32, &old_demand));
        try std.testing.expectEqual(calls, old_source.read_calls);

        var new_source = Reader{ .bytes = &wire };
        var new_demand = Demand.init(1);
        const packet = try read(std.testing.allocator, &new_source.interface, 32, &new_demand);
        defer std.testing.allocator.free(packet);
        try std.testing.expectEqualSlices(u8, &wire, packet);
        try std.testing.expectEqual(@as(u32, 0), new_demand.load());
        std.debug.print("lab04 cut={d} old_credit=0 outstanding_bytes=0 fresh_frame_bytes={d}\n", .{ cut, packet.len });
    }
}
