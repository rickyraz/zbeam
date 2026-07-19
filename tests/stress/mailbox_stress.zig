const std = @import("std");
const actor = @import("zbeam-actor");

const Message = struct { producer: u16, sequence: u32 };
const TestMailbox = actor.Mailbox(Message);

const Producer = struct {
    mailbox: *TestMailbox,
    producer: u16,
    count: u32,
};

fn produce(context: *const Producer) std.Io.Cancelable!void {
    for (0..context.count) |sequence| {
        context.mailbox.deliver(std.testing.io, .{
            .producer = context.producer,
            .sequence = @intCast(sequence),
        }) catch |err| switch (err) {
            error.Canceled => return error.Canceled,
            error.Closed => unreachable,
        };
    }
}

test "bounded mailbox preserves every producer sequence under contention" {
    const producer_count = 8;
    const messages_per_producer = 1_000;
    var storage: [64]Message = undefined;
    var mailbox = TestMailbox.init(&storage);
    defer mailbox.close(std.testing.io);

    var producers: [producer_count]Producer = undefined;
    var group: std.Io.Group = .init;
    defer group.cancel(std.testing.io);
    for (&producers, 0..) |*producer, index| {
        producer.* = .{
            .mailbox = &mailbox,
            .producer = @intCast(index),
            .count = messages_per_producer,
        };
        try group.concurrent(std.testing.io, produce, .{producer});
    }

    var next_expected = [_]u32{0} ** producer_count;
    const token = actor.Token.init(1);
    for (0..producer_count * messages_per_producer) |_| {
        const message = try mailbox.receive(std.testing.io, token);
        try std.testing.expect(message.producer < producer_count);
        try std.testing.expectEqual(next_expected[message.producer], message.sequence);
        next_expected[message.producer] += 1;
    }
    try group.await(std.testing.io);
    for (next_expected) |count| try std.testing.expectEqual(@as(u32, messages_per_producer), count);
}
