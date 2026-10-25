const std = @import("std");
const actor = @import("zbeam-actor");
const Message = struct { producer: usize, sequence: usize };
const Mailbox = actor.Mailbox(Message);

const Producer = struct {
    mailbox: *Mailbox,
    id: usize,
    failure: ?anyerror = null,

    fn run(self: *@This()) void {
        for (0..128) |sequence| {
            self.mailbox.deliver(std.testing.io, .{ .producer = self.id, .sequence = sequence }) catch |err| {
                self.failure = err;
                return;
            };
        }
    }
};

test "lab01: producer and capacity matrix preserves exact per-producer order" {
    const io = std.testing.io;
    for ([_]usize{ 1, 2, 4, 8, 16 }) |count| {
        for ([_]usize{ 1, 4, 64 }) |capacity| {
            var storage: [64]Message = undefined;
            var mailbox = Mailbox.init(storage[0..capacity]);
            defer mailbox.close(io);
            var producers: [16]Producer = undefined;
            var group: std.Io.Group = .init;
            defer group.cancel(io);
            for (producers[0..count], 0..) |*producer, id| {
                producer.* = .{ .mailbox = &mailbox, .id = id };
                try group.concurrent(io, Producer.run, .{producer});
            }
            var expected = [_]usize{0} ** 16;
            for (0..count * 128) |_| {
                const message = try mailbox.receive(io, .init(1));
                try std.testing.expect(message.producer < count);
                try std.testing.expectEqual(expected[message.producer], message.sequence);
                expected[message.producer] += 1;
            }
            try group.await(io);
            for (producers[0..count]) |producer| if (producer.failure) |err| return err;
            for (expected[0..count]) |received| try std.testing.expectEqual(@as(usize, 128), received);
            mailbox.close(io);
            try std.testing.expectError(error.Closed, mailbox.receive(io, .init(1)));
            std.debug.print("lab01 producers={d} capacity={d} received={d}\n", .{ count, capacity, count * 128 });
        }
    }
}

test "lab01: close rejects delivery and drains admitted messages" {
    const io = std.testing.io;
    var storage: [2]u8 = undefined;
    var mailbox = actor.Mailbox(u8).init(&storage);
    try mailbox.deliver(io, 10);
    try mailbox.deliver(io, 20);
    mailbox.close(io);
    try std.testing.expectError(error.Closed, mailbox.deliver(io, 30));
    try std.testing.expectEqual(@as(u8, 10), try mailbox.receive(io, .init(1)));
    try std.testing.expectEqual(@as(u8, 20), try mailbox.receive(io, .init(1)));
    try std.testing.expectError(error.Closed, mailbox.receive(io, .init(1)));
}
