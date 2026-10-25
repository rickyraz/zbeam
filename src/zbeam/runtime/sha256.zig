const std = @import("std");
const etf = @import("zbeam-etf");
const distribution = @import("zbeam-protocol").distribution;

/// Development-profile worker: SHA-256 of one bounded ETF binary, replying
/// to the sender PID with a 32-byte ETF binary. No asynchronous ownership.
pub const Sha256 = struct {
    limits: distribution.Limits = .{},

    pub fn handle(self: Sha256, allocator: std.mem.Allocator, bytes: []const u8) !?[]u8 {
        var packet = try distribution.decodePacket(allocator, bytes, self.limits);
        defer packet.deinit(allocator);
        if (packet == .tick) return try allocator.dupe(u8, &distribution.tickPacket());
        const route = try distribution.regSendDestination(&packet.message.control);
        if (!std.mem.eql(u8, route.name, "sha256")) return null;
        var payload = try packet.message.decodePayload(allocator, self.limits.etf);
        defer payload.deinit(allocator);
        if (payload != .binary) return error.InvalidPayload;
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(payload.binary, &digest, .{});
        var fields = [_]etf.Term{ .{ .integer = distribution.send }, .{ .atom = "" }, .{ .pid = route.from } };
        var control = etf.Term{ .tuple = &fields };
        var result = etf.Term{ .binary = &digest };
        return try distribution.encodePacket(allocator, &control, &result);
    }
};

test "sha256 worker replies to sender with known digest and rejects unsupported terms" {
    const allocator = std.testing.allocator;
    var fields = [_]etf.Term{
        .{ .integer = distribution.reg_send },
        .{ .pid = .{ .node = "client@127.0.0.1", .id = 10, .serial = 0, .creation = 1 } },
        .{ .atom = "" },
        .{ .atom = "sha256" },
    };
    var control = etf.Term{ .tuple = &fields };
    var data = etf.Term{ .binary = "abc" };
    const request = try distribution.encodePacket(allocator, &control, &data);
    defer allocator.free(request);
    const response = (try (Sha256{}).handle(allocator, request)).?;
    defer allocator.free(response);
    var reply = try distribution.decodePacket(allocator, response, .{});
    defer reply.deinit(allocator);
    try std.testing.expectEqual(distribution.send, reply.message.control.tuple[0].integer);
    try std.testing.expectEqual(@as(u32, 10), reply.message.control.tuple[2].pid.id);
    var result = try reply.message.decodePayload(allocator, .{});
    defer result.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 32), result.binary.len);
    try std.testing.expectEqualStrings("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", &std.fmt.bytesToHex(result.binary[0..32].*, .lower));
    try std.testing.expectError(error.LimitExceeded, (Sha256{ .limits = .{ .etf = .{ .max_binary_bytes = 2 } } }).handle(allocator, request));
    data = .{ .integer = 1 };
    const invalid = try distribution.encodePacket(allocator, &control, &data);
    defer allocator.free(invalid);
    try std.testing.expectError(error.InvalidPayload, (Sha256{}).handle(allocator, invalid));
    fields[3] = .{ .atom = "absent" };
    const ignored = try distribution.encodePacket(allocator, &control, &data);
    defer allocator.free(ignored);
    try std.testing.expectEqual(@as(?[]u8, null), try (Sha256{}).handle(allocator, ignored));
}
