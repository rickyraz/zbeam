const std = @import("std");
const etf = @import("zbeam-etf");
const dist = @import("zbeam-protocol").distribution;
const vectors = @import("zbeam-protocol-fixtures").m2b_vectors;
const testing = std.testing;

fn check(name: []const u8, control: *const etf.Term, payload: ?*const etf.Term) !void {
    var lines = std.mem.splitScalar(u8, vectors, '\n');
    var found = false;
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var columns = std.mem.splitScalar(u8, line, '\t');
        const key = columns.next() orelse return error.InvalidFixture;
        const hex = columns.next() orelse return error.InvalidFixture;
        try testing.expect(columns.next() == null);
        if (!std.mem.eql(u8, key, name)) continue;
        try testing.expect(!found);
        found = true;
        var scratch: [1024]u8 = undefined;
        const expected = try std.fmt.hexToBytes(&scratch, hex);
        const actual = try dist.encodePacket(testing.allocator, control, payload);
        defer testing.allocator.free(actual);
        try testing.expectEqualSlices(u8, expected, actual);
        var packet = try dist.decodePacket(testing.allocator, expected, .{});
        defer packet.deinit(testing.allocator);
        try testing.expect(packet == .message);
        if (payload) |_| {
            var decoded = try packet.message.decodePayload(testing.allocator, .{});
            defer decoded.deinit(testing.allocator);
            const encoded = try etf.encode(testing.allocator, &decoded);
            defer testing.allocator.free(encoded);
            try testing.expectEqualSlices(u8, packet.message.payload_etf.?, encoded);
        } else try testing.expect(packet.message.payload_etf == null);
    }
    try testing.expect(found);
}

test "independent OTP 25/26/27 two-worker frames encode and decode exactly" {
    const peer = etf.Pid{ .node = "peer@host", .creation = 2, .id = 4, .serial = 0 };
    const a = etf.Pid{ .node = "native@host", .creation = 1, .id = 1, .serial = 0 };
    const b = etf.Pid{ .node = "native@host", .creation = 1, .id = 2, .serial = 0 };
    const ref = etf.Reference{ .node = peer.node, .creation = 2, .len = 2, .ids = .{ 1, 2, 0, 0, 0 } };
    var reg = [_]etf.Term{ .{ .integer = 6 }, .{ .pid = peer }, .{ .atom = "" }, .{ .atom = "zbeam_workers" } };
    var send = [_]etf.Term{ .{ .integer = 2 }, .{ .atom = "" }, .{ .pid = a } };
    var cmd = [_]etf.Term{ .{ .atom = "discover" }, .{ .atom = "a" } };
    var request = [_]etf.Term{ .{ .pid = peer }, .{ .reference = ref }, .{ .tuple = &cmd } };
    try check("discover_a", &.{ .tuple = &reg }, &.{ .tuple = &request });
    cmd[1] = .{ .atom = "b" };
    try check("discover_b", &.{ .tuple = &reg }, &.{ .tuple = &request });
    cmd = .{ .{ .atom = "hash" }, .{ .binary = "abc" } };
    try check("hash_a", &.{ .tuple = &send }, &.{ .tuple = &request });
    send[2] = .{ .pid = b };
    try check("hash_b", &.{ .tuple = &send }, &.{ .tuple = &request });
    send[2] = .{ .pid = a };
    request[2] = .{ .atom = "stop" };
    try check("stop_a", &.{ .tuple = &send }, &.{ .tuple = &request });
    send[2] = .{ .pid = peer };
    var value = [_]etf.Term{ .{ .atom = "ok" }, .{ .pid = a } };
    var reply = [_]etf.Term{ .{ .reference = ref }, .{ .tuple = &value } };
    try check("reply_pid", &.{ .tuple = &send }, &.{ .tuple = &reply });
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash("abc", &digest, .{});
    value[1] = .{ .binary = &digest };
    try check("reply_digest", &.{ .tuple = &send }, &.{ .tuple = &reply });
    value = .{ .{ .atom = "error" }, .{ .atom = "noproc" } };
    try check("reply_noproc", &.{ .tuple = &send }, &.{ .tuple = &reply });
    reply[1] = .{ .atom = "ok" };
    try check("reply_stop", &.{ .tuple = &send }, &.{ .tuple = &reply });
    var monitor = [_]etf.Term{ .{ .integer = 19 }, .{ .pid = peer }, .{ .pid = a }, .{ .reference = ref } };
    try check("monitor_pid", &.{ .tuple = &monitor }, null);
    monitor[0] = .{ .integer = 20 };
    try check("demonitor_pid", &.{ .tuple = &monitor }, null);
    monitor[0] = .{ .integer = 19 };
    monitor[2] = .{ .atom = "zbeam_workers" };
    try check("monitor_name", &.{ .tuple = &monitor }, null);
    var exit = [_]etf.Term{ .{ .integer = 21 }, .{ .pid = a }, .{ .pid = peer }, .{ .reference = ref }, .{ .atom = "normal" } };
    try check("exit_normal", &.{ .tuple = &exit }, null);
}
