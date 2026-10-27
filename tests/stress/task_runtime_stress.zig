const std = @import("std");
const Runtime = @import("zbeam-runtime").TaskRuntime;

const Producer = struct {
    tasks: *Runtime,
    start: *std.Io.Event,
    first_accepted: *std.Io.Event,
    accepted: *[513]bool,
    failure: ?anyerror = null,

    fn run(self: *@This()) std.Io.Cancelable!void {
        try self.start.wait(std.testing.io);
        for (0..64) |_| {
            const id = self.tasks.trySend(1, "abc") catch |err| switch (err) {
                error.ActorStopped, error.WouldBlock => continue,
                error.Canceled => return error.Canceled,
                else => {
                    self.failure = err;
                    return;
                },
            };
            // Unique runtime request IDs give each sender a distinct element.
            self.accepted[id - 1] = true;
            self.first_accepted.set(std.testing.io);
        }
    }
};

test "task runtime stress: concurrent external senders join before storage destruction" {
    const io = std.testing.io;
    const tasks = try Runtime.create(std.testing.allocator, io, .{ "a", "b" });
    defer tasks.deinit() catch unreachable;
    defer _ = tasks.shutdown();
    var start: std.Io.Event = .unset;
    var first_accepted: std.Io.Event = .unset;
    var accepted: [513]bool = @splat(false);
    const initial = try tasks.trySend(1, "abc");
    accepted[initial - 1] = true;
    var producers: [8]Producer = undefined;
    var group: std.Io.Group = .init;
    defer group.cancel(io);
    for (&producers) |*producer| {
        producer.* = .{ .tasks = tasks, .start = &start, .first_accepted = &first_accepted, .accepted = &accepted };
        try group.concurrent(io, Producer.run, .{producer});
    }
    start.set(io);
    try first_accepted.waitTimeout(io, .{ .duration = .{ .raw = .fromSeconds(5), .clock = .awake } });
    try tasks.requestStop(1);
    try group.await(io);
    for (producers) |producer| if (producer.failure) |err| return err;
    _ = try tasks.stopAndJoin(1);
    try std.testing.expectError(error.ActorStopped, tasks.trySend(1, "late"));
    const sibling = try tasks.trySend(2, "abc");
    var received: [513]bool = @splat(false);
    var sibling_done = false;
    while (!sibling_done) {
        const result = (try tasks.nextResult()).?;
        if (result.actor_id == 2) {
            try std.testing.expectEqual(sibling, result.request_id);
            try std.testing.expectEqualStrings("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", &std.fmt.bytesToHex(result.outcome.digest, .lower));
            sibling_done = true;
        } else {
            try std.testing.expectEqual(@as(u64, 1), result.actor_id);
            try std.testing.expect(result.outcome != .handler_failed);
            try std.testing.expect(accepted[result.request_id - 1]);
            try std.testing.expect(!received[result.request_id - 1]);
            received[result.request_id - 1] = true;
        }
    }
    _ = tasks.shutdown();
    while (try tasks.nextResult()) |result| {
        try std.testing.expectEqual(@as(u64, 1), result.actor_id);
        try std.testing.expect(result.outcome != .handler_failed);
        try std.testing.expect(accepted[result.request_id - 1]);
        try std.testing.expect(!received[result.request_id - 1]);
        received[result.request_id - 1] = true;
    }
    try std.testing.expectEqual(accepted, received);
    var count: usize = 0;
    for (accepted) |present| if (present) {
        count += 1;
    };
    try std.testing.expect(count >= 2 and count <= 5);
    std.debug.print("task-runtime attempted=513 accepted={d} terminal={d} external_senders_joined=8\n", .{ count, count });
}
