const std = @import("std");
const runtime = @import("zbeam-runtime");

const frames = 1024;
const payload_size = 64 * 1024;

const SlowActor = struct {
    server: *std.Io.net.Server,
    stalled: std.Io.Event = .unset,
    resume_event: std.Io.Event = .unset,
    done: std.Io.Event = .unset,
    received: std.atomic.Value(usize) = .init(0),
    failure: ?anyerror = null,

    pub fn handle(self: *SlowActor, _: std.mem.Allocator, _: []const u8) !?[]u8 {
        if (self.received.fetchAdd(1, .monotonic) == 0) {
            self.stalled.set(std.testing.io);
            try self.resume_event.wait(std.testing.io);
        }
        return null;
    }

    fn run(self: *SlowActor) void {
        defer self.done.set(std.testing.io);
        self.serve() catch |err| {
            self.failure = err;
        };
    }

    fn serve(self: *SlowActor) !void {
        const io = std.testing.io;
        const stream = try self.server.accept(io);
        defer stream.close(io);
        // Exercise the real post-authentication dispatcher with a paused actor.
        runtime.node.dispatch(io, std.testing.allocator, stream, .{
            .node_name = "slow@host",
            .cookie = "cookie",
            .creation = 1,
            .max_messages = 0,
            .limits = .{ .max_packet_bytes = payload_size },
        }, self) catch |err| {
            if (err != error.EndOfStream) return err;
        };
    }
};

const Sender = struct {
    address: std.Io.net.IpAddress,
    sent: std.atomic.Value(usize) = .init(0),
    done: std.Io.Event = .unset,
    failure: ?anyerror = null,

    fn run(self: *Sender) void {
        defer self.done.set(std.testing.io);
        self.send() catch |err| {
            self.failure = err;
        };
    }

    fn send(self: *Sender) !void {
        const stream = try self.address.connect(std.testing.io, .{ .mode = .stream });
        defer stream.close(std.testing.io);
        var writer = stream.writer(std.testing.io, &.{});
        var packet = [_]u8{0} ** (payload_size + 4);
        std.mem.writeInt(u32, packet[0..4], payload_size, .big);
        for (0..frames) |_| {
            try writer.interface.writeAll(&packet);
            _ = self.sent.fetchAdd(1, .monotonic);
        }
    }
};

test "paused actor stops TCP consumption and sender resumes after grant" {
    try exercise(false);
}

test "canceling a paused actor releases its owned packet and joins network tasks" {
    try exercise(true);
}

fn exercise(cancel: bool) !void {
    const io = std.testing.io;
    const address: std.Io.net.IpAddress = .{ .ip4 = .loopback(0) };
    var server = try address.listen(io, .{ .reuse_address = true });
    defer server.deinit(io);
    var actor = SlowActor{ .server = &server };
    var sender = Sender{ .address = server.socket.address };
    var group: std.Io.Group = .init;
    defer group.cancel(io);
    try group.concurrent(io, SlowActor.run, .{&actor});
    try group.concurrent(io, Sender.run, .{&sender});
    try actor.stalled.waitTimeout(io, .{ .duration = .{ .raw = .fromSeconds(5), .clock = .awake } });
    try std.Io.sleep(io, .fromMilliseconds(100), .awake);
    try std.testing.expectEqual(@as(usize, 1), actor.received.load(.monotonic));
    try std.testing.expect(sender.sent.load(.monotonic) < frames);
    try std.testing.expect(!sender.done.isSet());
    if (cancel) {
        group.cancel(io);
        try std.testing.expectEqual(error.Canceled, actor.failure.?);
        return;
    }
    actor.resume_event.set(io);
    try sender.done.waitTimeout(io, .{ .duration = .{ .raw = .fromSeconds(10), .clock = .awake } });
    try actor.done.waitTimeout(io, .{ .duration = .{ .raw = .fromSeconds(10), .clock = .awake } });
    try group.await(io);
    if (sender.failure) |err| return err;
    if (actor.failure) |err| return err;
    try std.testing.expectEqual(@as(usize, frames), sender.sent.load(.monotonic));
    try std.testing.expectEqual(@as(usize, frames), actor.received.load(.monotonic));
}
