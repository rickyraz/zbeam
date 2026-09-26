const std = @import("std");
const etf = @import("zbeam-etf");
const protocol = @import("zbeam-protocol");
const fixtures = @import("zbeam-protocol-fixtures");

comptime {
    _ = @import("fixture_manifest.zig");
}

test "public pure wire batteries remain importable" {
    std.testing.refAllDecls(etf);
    std.testing.refAllDecls(protocol);
}

test "OTP 23+ new handshake fields match structural wire vectors" {
    const allocator = std.testing.allocator;
    const name = try protocol.handshake.encodeName(allocator, .{
        .flags = 0x1122_3344_5566_7788,
        .creation = 0xaabb_ccdd,
        .node_name = "a@b",
    });
    defer allocator.free(name);
    try std.testing.expectEqualSlices(u8, &fixtures.new_name, name);

    const challenge = try protocol.handshake.encodeChallenge(allocator, .{
        .flags = 0x1122_3344_5566_7788,
        .challenge = 0x0102_0304,
        .creation = 0xaabb_ccdd,
        .node_name = "a@b",
    });
    defer allocator.free(challenge);
    try std.testing.expectEqualSlices(u8, &fixtures.new_challenge, challenge);

    const status = try protocol.handshake.encodeStatus(allocator, .ok);
    defer allocator.free(status);
    try std.testing.expectEqualSlices(u8, &fixtures.status_ok, status);
}

test "distribution framing vectors decode deterministically" {
    var tick = try protocol.distribution.decodePacket(std.testing.allocator, &fixtures.distribution_tick, .{});
    defer tick.deinit(std.testing.allocator);
    try std.testing.expect(tick == .tick);

    var packet = try protocol.distribution.decodePacket(std.testing.allocator, &fixtures.pass_through_atom, .{});
    defer packet.deinit(std.testing.allocator);
    try std.testing.expect(packet == .message);
    try std.testing.expectEqualStrings("x", packet.message.control.atom);
    try std.testing.expect(packet.message.payload_etf == null);
}

test "MVP capability profile excludes optional monitors caches and fragments" {
    try std.testing.expectEqual(@as(u64, 0), protocol.flags.m1 & protocol.flags.dist_monitor);
    // DFLAG_DIST_HDR_ATOM_CACHE and DFLAG_FRAGMENTS, OTP distribution flags.
    try std.testing.expectEqual(@as(u64, 0), protocol.flags.m1 & (0x2000 | 0x0080_0000));
    for ([_]u8{ 68, 69, 70 }) |header| {
        try std.testing.expectError(error.UnexpectedHeader, protocol.distribution.decodePacket(std.testing.allocator, &.{ 0, 0, 0, 2, 131, header }, .{}));
    }
}

test "REG_SEND requires the legacy cookie atom and bounded ETF storage" {
    var fields = [_]etf.Term{
        .{ .integer = protocol.distribution.reg_send },
        .{ .pid = .{ .node = "n@host", .id = 1, .serial = 0, .creation = 1 } },
        .{ .integer = 0 },
        .{ .atom = "echo" },
    };
    var control = etf.Term{ .tuple = &fields };
    try std.testing.expectError(error.InvalidControl, protocol.distribution.regSendDestination(&control));
    fields[2] = .{ .atom = "" };
    const bytes = try protocol.distribution.encodePacket(std.testing.allocator, &control, null);
    defer std.testing.allocator.free(bytes);
    try std.testing.expectError(error.PacketTooLarge, protocol.distribution.decodePacket(std.testing.allocator, bytes, .{ .max_packet_bytes = 1 }));
    try std.testing.expectError(error.LimitExceeded, protocol.distribution.decodePacket(std.testing.allocator, bytes, .{ .etf = .{ .max_allocated_bytes = 0 } }));
    try std.testing.expectEqualStrings("echo", (try protocol.distribution.regSendDestination(&control)).name);
}

test "malformed handshake name length is rejected" {
    const truncated = [_]u8{
        'N',
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        2,
        'a',
    };
    try std.testing.expectError(error.Truncated, protocol.handshake.decodeName(std.testing.allocator, &truncated));
}
