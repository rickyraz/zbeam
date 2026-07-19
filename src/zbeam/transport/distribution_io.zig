const std = @import("std");

/// Reads one distribution frame while preserving its four-byte header for the
/// pure protocol decoder. Length is bounded before allocation at the network
/// trust boundary.
pub fn readPacket(allocator: std.mem.Allocator, reader: *std.Io.Reader, max_packet_bytes: u32) ![]u8 {
    var header: [4]u8 = undefined;
    try reader.readSliceAll(&header);
    const length = readU32(&header);
    if (length > max_packet_bytes) return error.PacketTooLarge;
    const packet = try allocator.alloc(u8, @as(usize, length) + 4);
    errdefer allocator.free(packet);
    @memcpy(packet[0..4], &header);
    try reader.readSliceAll(packet[4..]);
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

/// Combines four network-order octets into the protocol's 32-bit frame length.
fn readU32(bytes: *const [4]u8) u32 {
    return (@as(u32, bytes[0]) << 24) | (@as(u32, bytes[1]) << 16) |
        (@as(u32, bytes[2]) << 8) | bytes[3];
}
