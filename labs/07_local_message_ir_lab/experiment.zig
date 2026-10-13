const std = @import("std");
const etf = @import("zbeam-etf");
const actor = @import("zbeam-actor");

const Envelope = struct {
    sequence: u32,
    bytes: [32]u8 = @splat(0),
    used: usize,

    fn fromTerm(term: etf.Term) !Envelope {
        const fields = switch (term) {
            .tuple => |items| items,
            else => return error.NotEnvelope,
        };
        if (fields.len != 2 or fields[0] != .integer or fields[1] != .binary) return error.NotEnvelope;
        const sequence = std.math.cast(u32, fields[0].integer) orelse return error.SequenceOutOfRange;
        const bytes = fields[1].binary;
        if (bytes.len > 32) return error.PayloadTooLarge;
        var result = Envelope{ .sequence = sequence, .used = bytes.len };
        @memcpy(result.bytes[0..bytes.len], bytes);
        return result;
    }
};

test "lab07: copied local envelope survives wire and decoded-term release" {
    const allocator = std.testing.allocator;
    var fields = [_]etf.Term{ .{ .integer = 7 }, .{ .binary = "hello" } };
    const wire = try etf.encode(allocator, &.{ .tuple = &fields });
    const envelope = blk: {
        defer allocator.free(wire);
        var term = try etf.decode(allocator, wire, .{});
        defer term.deinit(allocator);
        break :blk try Envelope.fromTerm(term);
    };
    var slots: [1]Envelope = undefined;
    var mailbox = actor.Mailbox(Envelope).init(&slots);
    defer mailbox.close(std.testing.io);
    try mailbox.deliver(std.testing.io, envelope);
    const received = try mailbox.receive(std.testing.io, .init(1));
    try std.testing.expectEqual(@as(u32, 7), received.sequence);
    try std.testing.expectEqualStrings("hello", received.bytes[0..received.used]);
    std.debug.print("lab07 boundary_decodes=1 local_reencodes=0 payload_copy_bytes=5 envelope_storage_bytes={d}\n", .{@sizeOf(Envelope)});
}

test "lab07: conversion rejects shape, range and capacity violations" {
    try std.testing.expectError(error.NotEnvelope, Envelope.fromTerm(.nil));
    var fields = [_]etf.Term{ .nil, .{ .binary = "" } };
    try std.testing.expectError(error.NotEnvelope, Envelope.fromTerm(.{ .tuple = fields[0..1] }));
    try std.testing.expectError(error.NotEnvelope, Envelope.fromTerm(.{ .tuple = &fields }));
    fields[0] = .{ .integer = -1 };
    try std.testing.expectError(error.SequenceOutOfRange, Envelope.fromTerm(.{ .tuple = &fields }));
    fields[0] = .{ .integer = @as(i64, std.math.maxInt(u32)) + 1 };
    try std.testing.expectError(error.SequenceOutOfRange, Envelope.fromTerm(.{ .tuple = &fields }));
    fields[0] = .{ .integer = 0 };
    fields[1] = .{ .binary = "x" ** 33 };
    try std.testing.expectError(error.PayloadTooLarge, Envelope.fromTerm(.{ .tuple = &fields }));
    fields[1] = .{ .binary = "x" ** 32 };
    try std.testing.expectEqual(@as(usize, 32), (try Envelope.fromTerm(.{ .tuple = &fields })).used);
}
