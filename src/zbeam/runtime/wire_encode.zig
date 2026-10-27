//! Bounded output encoding for the proposed two-worker profile. Returned bytes
//! borrow the caller's scratch buffer until the write completes or is dropped.
const std = @import("std");
const etf = @import("zbeam-etf");
const protocol = @import("zbeam-protocol");
const dist = protocol.distribution;
const monitor = protocol.monitor;

pub const scratch_bytes = 16 * 1024;
pub const ErrorAtom = enum { bad_request, noproc, stopped, canceled, handler_failed };
pub const Result = union(enum) { pid: etf.Pid, digest: [32]u8, ok, failure: ErrorAtom };
pub const Reason = enum { normal, noproc };

/// Uses only caller-owned bounded storage, including ETF encoder temporaries.
pub fn reply(scratch: *[scratch_bytes]u8, to: etf.Pid, reference: etf.Reference, result: Result) ![]const u8 {
    var allocator = std.heap.FixedBufferAllocator.init(scratch);
    var control = [_]etf.Term{ .{ .integer = dist.send }, .{ .atom = "" }, .{ .pid = to } };
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
        for ([_]Reason{ .normal, .noproc }) |reason| {
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
