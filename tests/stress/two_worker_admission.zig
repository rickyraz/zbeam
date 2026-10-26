const std = @import("std");
const actor = @import("zbeam-actor");
const runtime = @import("zbeam-runtime");
const Message = struct { used: u16 = 1, bytes: [1024]u8 = @splat(90) };
const Mailbox = actor.Mailbox(Message);
const Registry = runtime.Runtime(Message);
const Worker = struct {
    mailbox: *Mailbox,
    token: actor.Token,
    pause: bool,
    entered: std.Io.Event = .unset,
    resume_event: std.Io.Event = .unset,
    processed: std.Io.Event = .unset,
    count: usize = 0,
    failure: ?anyerror = null,
    fn run(self: *@This()) void {
        self.work() catch |err| {
            self.failure = err;
        };
    }
    fn work(self: *@This()) !void {
        const io = std.testing.io;
        while (true) {
            const message = self.mailbox.receive(io, self.token) catch |err| {
                if (err == error.Closed) return;
                return err;
            };
            if (message.used > message.bytes.len or message.bytes[0] != 90) return error.BadMessage;
            if (self.pause and self.count == 0) {
                self.entered.set(io);
                try self.resume_event.wait(io);
            }
            self.count += 1;
            self.processed.set(io);
        }
    }
};
const Sender = struct {
    registry: *Registry,
    started: std.Io.Event = .unset,
    failure: ?anyerror = null,
    fn run(self: *@This()) void {
        self.started.set(std.testing.io);
        self.registry.sendNamed("slow", .{}) catch |err| {
            self.failure = err;
        };
    }
};

test "full slow mailbox permits admitted fast progress; terminate joins resolved sends" {
    const io = std.testing.io;
    var slow_storage: [4]Message = undefined;
    var fast_storage: [4]Message = undefined;
    var slow_box = Mailbox.init(&slow_storage);
    var fast_box = Mailbox.init(&fast_storage);
    var registry = Registry.init(std.testing.allocator, io);
    defer registry.deinit();
    const slow_id = try registry.spawn("slow", &slow_box);
    const fast_id = try registry.spawn("fast", &fast_box);
    var slow = Worker{ .mailbox = &slow_box, .token = slow_id.token, .pause = true };
    var fast = Worker{ .mailbox = &fast_box, .token = fast_id.token, .pause = false };
    var sender = Sender{ .registry = &registry };
    var group: std.Io.Group = .init;
    defer group.cancel(io);
    try group.concurrent(io, Worker.run, .{&slow});
    try group.concurrent(io, Worker.run, .{&fast});
    try registry.sendNamed("slow", .{});
    try slow.entered.waitTimeout(io, .{ .duration = .{ .raw = .fromSeconds(2), .clock = .awake } });
    for (0..4) |_| try registry.sendNamed("slow", .{});
    try group.concurrent(io, Sender.run, .{&sender});
    try sender.started.wait(io);
    try registry.sendNamed("fast", .{});
    try fast.processed.waitTimeout(io, .{ .duration = .{ .raw = .fromSeconds(2), .clock = .awake } });
    try std.testing.expect(registry.terminate(slow_id.id));
    try std.testing.expect(registry.terminate(fast_id.id));
    try std.testing.expectError(error.ActorNotFound, registry.sendNamed("slow", .{}));
    try std.testing.expectError(error.Closed, slow_box.deliver(io, .{}));
    slow.resume_event.set(io);
    try group.await(io);
    try std.testing.expectEqual(@as(usize, 1), fast.count);
    try std.testing.expect(slow.failure == null and fast.failure == null);
    // An in-flight Queue put can finish during close; account for exactly that send.
    if (sender.failure) |failure| {
        try std.testing.expect(failure == error.Closed or failure == error.ActorNotFound);
        try std.testing.expectEqual(@as(usize, 5), slow.count);
    } else {
        try std.testing.expectEqual(@as(usize, 6), slow.count);
    }
    try std.testing.expectEqual(@as(usize, 4), slow_box.capacity());
}

test "unknown next destination requires minimum credit rather than a sum" {
    const credits = [_]u32{ 0, 4 };
    var demand = actor.Demand.init(@min(credits[0], credits[1]));
    try std.testing.expectEqual(@as(u32, 0), demand.load());
    try std.testing.expect(!demand.tryConsume());
}
