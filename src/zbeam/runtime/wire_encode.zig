//! Bounded output encoding for the two-worker profiles. Returned bytes borrow
//! the caller's scratch buffer until the write completes or is dropped.
const std = @import("std");
const etf = @import("zbeam-etf");
const protocol = @import("zbeam-protocol");
const dist = protocol.distribution;
const monitor = protocol.monitor;

pub const scratch_bytes = 16 * 1024;
/// Largest custom-call binary; its bytes follow a bounded header on the wire.
pub const max_binary = 64 * 1024;
pub const ErrorAtom = enum { bad_request, noproc, stopped, canceled, handler_failed };
pub const Result = union(enum) { pid: etf.Pid, digest: [32]u8, ok, failure: ErrorAtom };
pub const Reason = enum { normal, noproc, handler_failed };

/// Uses only caller-owned bounded storage, including ETF encoder temporaries.
pub fn reply(scratch: *[scratch_bytes]u8, to: etf.Pid, reference: etf.Reference, result: Result) ![]u8 {
    var pair: [2]etf.Term = undefined;
    const value: etf.Term = switch (result) {
        .ok => .{ .atom = "ok" },
        .pid => |pid| blk: {
            pair = .{ .{ .atom = "ok" }, .{ .pid = pid } };
            break :blk .{ .tuple = &pair };
        },
        .digest => |*digest| blk: {
            pair = .{ .{ .atom = "ok" }, .{ .binary = digest } };
            break :blk .{ .tuple = &pair };
        },
        .failure => |failure| blk: {
            pair = .{ .{ .atom = "error" }, .{ .atom = @tagName(failure) } };
            break :blk .{ .tuple = &pair };
        },
    };
    return send(scratch, to, reference, value);
}

/// Returns the frame header for `{Ref, {ok, Binary}}` with a `len`-byte binary.
/// The caller writes exactly those bytes after the header, without copying them.
pub fn binaryReplyHeader(scratch: *[scratch_bytes]u8, to: etf.Pid, reference: etf.Reference, len: usize) ![]u8 {
    if (len > max_binary) return error.OutputTooLarge;
    var pair = [_]etf.Term{ .{ .atom = "ok" }, .{ .binary = "" } };
    const header = try send(scratch, to, reference, .{ .tuple = &pair });
    // The empty binary is the frame's last term: BINARY_EXT (109) and length 0.
    std.debug.assert(std.mem.eql(u8, header[header.len - 5 ..], &.{ 109, 0, 0, 0, 0 }));
    std.mem.writeInt(u32, header[header.len - 4 ..][0..4], @intCast(len), .big);
    const frame = std.mem.readInt(u32, header[0..4], .big) + @as(u32, @intCast(len));
    std.mem.writeInt(u32, header[0..4], frame, .big);
    return header;
}

fn send(scratch: *[scratch_bytes]u8, to: etf.Pid, reference: etf.Reference, value: etf.Term) ![]u8 {
    var allocator = std.heap.FixedBufferAllocator.init(scratch);
    var control = [_]etf.Term{ .{ .integer = dist.send }, .{ .atom = "" }, .{ .pid = to } };
    var body = [_]etf.Term{ .{ .reference = reference }, value };
    return dist.encodePacket(allocator.allocator(), &.{ .tuple = &control }, &.{ .tuple = &body });
}

pub fn monitorExit(scratch: *[scratch_bytes]u8, target: monitor.Target, to: etf.Pid, reference: etf.Reference, reason: Reason) ![]const u8 {
    var allocator = std.heap.FixedBufferAllocator.init(scratch);
    var control = [_]etf.Term{ .{ .integer = monitor.monitor_p_exit }, target.term(), .{ .pid = to }, .{ .reference = reference }, .{ .atom = @tagName(reason) } };
    return dist.encodePacket(allocator.allocator(), &.{ .tuple = &control }, null);
}

const testing = std.testing;
const test_pid = etf.Pid{ .node = "peer@host", .id = 9, .serial = 8, .creation = 3 };
const test_ref = etf.Reference{ .node = "peer@host", .creation = 3, .ids = .{ 1, 2, 3, 4, 5 }, .len = 5 };

test "bounded reply encoding preserves reference and exact digest" {
    var scratch: [scratch_bytes]u8 = undefined;
    const digest: [32]u8 = @splat(42);
    const bytes = try reply(&scratch, test_pid, test_ref, .{ .digest = digest });
    var packet = try dist.decodePacket(testing.allocator, bytes, .{});
    defer packet.deinit(testing.allocator);
    try testing.expectEqual(dist.send, packet.message.control.tuple[0].integer);
    try testing.expect(packet.message.control.tuple[2].pid.eql(test_pid));
    var payload = try packet.message.decodePayload(testing.allocator, .{});
    defer payload.deinit(testing.allocator);
    try testing.expect(payload.tuple[0].reference.eql(test_ref));
    try testing.expectEqualStrings("ok", payload.tuple[1].tuple[0].atom);
    try testing.expectEqualSlices(u8, &digest, payload.tuple[1].tuple[1].binary);
}

test "binary reply header plus payload equals the generic encoding" {
    var scratch: [scratch_bytes]u8 = undefined;
    const output = try testing.allocator.alloc(u8, max_binary + 1);
    defer testing.allocator.free(output);
    for (output, 0..) |*byte, i| byte.* = @truncate(i *% 31);
    var name: [255]u8 = @splat('n');
    const long = etf.Pid{ .node = &name, .id = 1, .serial = 2, .creation = 3 };
    const long_ref = etf.Reference{ .node = &name, .creation = 3, .ids = .{ 1, 2, 3, 4, 5 }, .len = 5 };
    for ([_]struct { etf.Pid, etf.Reference }{ .{ test_pid, test_ref }, .{ long, long_ref } }) |target| {
        for ([_]usize{ 0, 1, 32, 33, 4096, max_binary }) |len| {
            const header = try binaryReplyHeader(&scratch, target[0], target[1], len);
            var control = [_]etf.Term{ .{ .integer = dist.send }, .{ .atom = "" }, .{ .pid = target[0] } };
            var pair = [_]etf.Term{ .{ .atom = "ok" }, .{ .binary = output[0..len] } };
            var body = [_]etf.Term{ .{ .reference = target[1] }, .{ .tuple = &pair } };
            const expected = try dist.encodePacket(testing.allocator, &.{ .tuple = &control }, &.{ .tuple = &body });
            defer testing.allocator.free(expected);
            try testing.expectEqualSlices(u8, expected[0..header.len], header);
            try testing.expectEqualSlices(u8, expected[header.len..], output[0..len]);
        }
    }
    try testing.expectError(error.OutputTooLarge, binaryReplyHeader(&scratch, test_pid, test_ref, max_binary + 1));
}

test "monitor exit and all bounded reply forms fit for maximum node atoms" {
    var scratch: [scratch_bytes]u8 = undefined;
    var name: [255]u8 = @splat('n');
    const pid = etf.Pid{ .node = &name, .id = 1, .serial = 2, .creation = 3 };
    const ref = etf.Reference{ .node = &name, .creation = 3, .ids = .{ 1, 2, 3, 4, 5 }, .len = 5 };
    for ([_]Result{ .{ .pid = pid }, .{ .digest = @splat(0) }, .ok, .{ .failure = .handler_failed } }) |result| {
        const bytes = try reply(&scratch, pid, ref, result);
        var packet = try dist.decodePacket(testing.allocator, bytes, .{});
        defer packet.deinit(testing.allocator);
        var payload = try packet.message.decodePayload(testing.allocator, .{});
        defer payload.deinit(testing.allocator);
        try testing.expect(payload.tuple[0].reference.eql(ref));
        const value = payload.tuple[1];
        switch (result) {
            .pid => |expected| {
                try testing.expectEqualStrings("ok", value.tuple[0].atom);
                try testing.expect(value.tuple[1].pid.eql(expected));
            },
            .digest => |expected| {
                try testing.expectEqualStrings("ok", value.tuple[0].atom);
                try testing.expectEqualSlices(u8, &expected, value.tuple[1].binary);
            },
            .ok => try testing.expectEqualStrings("ok", value.atom),
            .failure => |reason| {
                try testing.expectEqualStrings("error", value.tuple[0].atom);
                try testing.expectEqualStrings(@tagName(reason), value.tuple[1].atom);
            },
        }
    }
    for ([_]monitor.Target{ .{ .pid = pid }, .{ .name = &name } }) |target| {
        for ([_]Reason{ .normal, .noproc, .handler_failed }) |reason| {
            const bytes = try monitorExit(&scratch, target, pid, ref, reason);
            var packet = try dist.decodePacket(testing.allocator, bytes, .{});
            defer packet.deinit(testing.allocator);
            const decoded = try monitor.parse(&packet.message.control);
            try testing.expect(decoded.target.eql(target) and decoded.watcher.eql(pid) and decoded.reference.eql(ref));
            try testing.expectEqualStrings(@tagName(reason), decoded.reason.?.atom);
        }
    }
}

test "oversized atoms and invalid references fail within fixed scratch" {
    var scratch: [scratch_bytes]u8 = undefined;
    var huge: [32 * 1024]u8 = @splat('n');
    var to = test_pid;
    to.node = &huge;
    try testing.expectError(error.OutOfMemory, reply(&scratch, to, test_ref, .ok));
    var bad = test_ref;
    bad.len = 0;
    try testing.expectError(error.InvalidReference, reply(&scratch, test_pid, bad, .ok));
}
