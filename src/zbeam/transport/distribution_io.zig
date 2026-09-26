const std = @import("std");

/// The injected credit source keeps transport independent of the actor battery.
/// An unbuffered reader is required: read-ahead would spend future demand.
/// Any read error is terminal for this connection; its reserved credit is not
/// reusable because part of a frame may already have been consumed.
pub fn readDemandedPacket(allocator: std.mem.Allocator, reader: *std.Io.Reader, max_packet_bytes: u32, demand: anytype) ![]u8 {
    if (reader.buffer.len != 0) return error.BufferedReader;
    if (!demand.tryConsume()) return error.NoDemand;
    return readPacket(allocator, reader, max_packet_bytes);
}

/// Reads one distribution frame while preserving its four-byte header for the
/// pure protocol decoder. Length is bounded before allocation at the network
/// trust boundary.
pub fn readPacket(allocator: std.mem.Allocator, reader: *std.Io.Reader, max_packet_bytes: u32) ![]u8 {
    var header: [4]u8 = undefined;
    const received = try reader.readSliceShort(&header);
    if (received == 0) return error.EndOfStream;
    if (received != header.len) return error.Truncated;
    const length = readU32(&header);
    if (length > max_packet_bytes) return error.PacketTooLarge;
    const allocation_size = std.math.add(usize, length, 4) catch return error.PacketTooLarge;
    const packet = try allocator.alloc(u8, allocation_size);
    errdefer allocator.free(packet);
    @memcpy(packet[0..4], &header);
    reader.readSliceAll(packet[4..]) catch |err| return if (err == error.EndOfStream) error.Truncated else err;
    return packet;
}

/// Refuses internally inconsistent frames before writing and flushes because a
/// tick or reply must reach the peer promptly to advance connection state.
pub fn writePacket(writer: *std.Io.Writer, packet: []const u8) !void {
    if (packet.len < 4) return error.Truncated;
    if (readU32(packet[0..4]) != packet.len - 4) return error.LengthMismatch;
    try writer.writeAll(packet);
    try writer.flush();
}

test "framing distinguishes clean EOF from truncated headers and payloads" {
    var empty = std.Io.Reader.fixed(&.{});
    try std.testing.expectError(error.EndOfStream, readPacket(std.testing.allocator, &empty, 1024));
    for ([_][]const u8{ &.{0}, &.{ 0, 0, 0 }, &.{ 0, 0, 0, 2, 112 } }) |bytes| {
        var reader = std.Io.Reader.fixed(bytes);
        try std.testing.expectError(error.Truncated, readPacket(std.testing.allocator, &reader, 1024));
    }
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var oversized = std.Io.Reader.fixed(&.{ 0, 0, 4, 1 });
    try std.testing.expectError(error.PacketTooLarge, readPacket(failing.allocator(), &oversized, 1024));
}

/// Combines four network-order octets into the protocol's 32-bit frame length.
fn readU32(bytes: *const [4]u8) u32 {
    return (@as(u32, bytes[0]) << 24) | (@as(u32, bytes[1]) << 16) |
        (@as(u32, bytes[2]) << 8) | bytes[3];
}
