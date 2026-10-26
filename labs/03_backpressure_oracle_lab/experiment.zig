const std = @import("std");
const Demand = @import("zbeam-actor").Demand;
const read = @import("zbeam-transport").distribution_io.readDemandedPacket;
const Reader = @import("lab-reader");

test "lab03: zero credit is a zero-read and zero-allocation oracle" {
    var source = Reader{ .bytes = &.{ 0, 0, 0, 1, 112, 0, 0, 0, 0 }, .chunk = 1 };
    var demand = Demand.init(0);
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    for (0..100) |_| try std.testing.expectError(error.NoDemand, read(failing.allocator(), &source.interface, 16, &demand));
    try std.testing.expectEqual(@as(usize, 0), source.read_calls);
    try std.testing.expect(!failing.has_induced_failure);
    try demand.grant(1);
    const packet = try read(std.testing.allocator, &source.interface, 16, &demand);
    defer std.testing.allocator.free(packet);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0, 1, 112 }, packet);
    try std.testing.expectEqual(@as(usize, 5), source.consumed);
    try std.testing.expectEqual(@as(usize, 4), source.bytes.len);
    const calls = source.read_calls;
    try std.testing.expectError(error.NoDemand, read(failing.allocator(), &source.interface, 16, &demand));
    try std.testing.expectEqual(calls, source.read_calls);
    std.debug.print("lab03 paused_attempts=100 paused_reads=0 allocation_attempts=0 admitted_bytes={d} unread_bytes={d}\n", .{ source.consumed, source.bytes.len });
}

test "lab03: buffered input is rejected without spending credit" {
    var source = std.Io.Reader.fixed(&.{ 0, 0, 0, 0 });
    var demand = Demand.init(1);
    try std.testing.expectError(error.BufferedReader, read(std.testing.allocator, &source, 16, &demand));
    try std.testing.expectEqual(@as(u32, 1), demand.load());
    try std.testing.expectEqual(@as(usize, 0), source.seek);
}
