const std = @import("std");

/// Logical receive authority issued with an actor handle. Zero is reserved as
/// "unclaimed" in the mailbox atomic; runtime IDs therefore start at one.
pub const Token = struct {
    id: u64,

    pub fn init(id: u64) Token {
        std.debug.assert(id != 0);
        return .{ .id = id };
    }
};

/// Adds actor semantics to Zig's bounded, thread-safe `std.Io.Queue`.
/// Storage is caller-supplied so capacity is visible and cannot silently grow.
pub fn Mailbox(comptime Message: type) type {
    return struct {
        const Self = @This();

        queue: std.Io.Queue(Message),
        owner: std.atomic.Value(u64) = .init(0),
        receiving: std.atomic.Value(bool) = .init(false),

        /// The buffer length is the hard queue capacity; at least one slot is
        /// required for a useful mailbox.
        pub fn init(buffer: []Message) Self {
            std.debug.assert(buffer.len > 0);
            return .{ .queue = .init(buffer) };
        }

        /// Wakes blocked operations and rejects future delivery while allowing
        /// already-buffered messages to drain according to `std.Io.Queue`.
        pub fn close(self: *Self, io: std.Io) void {
            self.queue.close(io);
        }

        /// Blocks when the bounded mailbox is full, propagating backpressure to
        /// the delivering task.
        pub fn deliver(self: *Self, io: std.Io, message: Message) !void {
            try self.queue.putOne(io, message);
        }

        /// Never waits for capacity or links a pending putter. On any error the
        /// caller retains the message; success transfers one complete element.
        /// The queue mutex can still contend and introduce cancellation.
        pub fn tryDeliver(self: *Self, io: std.Io, message: Message) !void {
            if (try self.queue.put(io, &.{message}, 0) == 0) return error.WouldBlock;
        }

        /// Enforces one logical actor token as the mailbox consumer.
        pub fn receive(self: *Self, io: std.Io, token: Token) !Message {
            try self.claim(token);
            if (self.receiving.cmpxchgStrong(false, true, .acq_rel, .acquire) != null) return error.ConcurrentReceive;
            defer self.receiving.store(false, .release);
            return self.queue.getOne(io);
        }

        /// Exposes the fixed bound for diagnostics and admission policy.
        pub fn capacity(self: *const Self) usize {
            return self.queue.capacity();
        }

        /// Atomically changes owner from sentinel zero to one logical actor.
        /// Acquire/release ordering publishes the winning identity to every
        /// producer/consumer thread; later calls must present the same token.
        fn claim(self: *Self, token: Token) error{NotOwner}!void {
            if (token.id == 0) return error.NotOwner;
            const previous = self.owner.cmpxchgStrong(0, token.id, .acq_rel, .acquire);
            if (previous) |owner| {
                if (owner != token.id) return error.NotOwner;
            }
        }
    };
}

test "mailbox enforces a single logical consumer" {
    const io = std.testing.io;
    var storage: [2]u8 = undefined;
    var mailbox = Mailbox(u8).init(&storage);
    defer mailbox.close(io);
    try mailbox.deliver(io, 1);
    try mailbox.deliver(io, 2);
    try std.testing.expectEqual(@as(u8, 1), try mailbox.receive(io, .init(1)));
    try std.testing.expectError(error.NotOwner, mailbox.receive(io, .init(2)));
    try std.testing.expectEqual(@as(u8, 2), try mailbox.receive(io, .init(1)));
    try std.testing.expectError(error.NotOwner, mailbox.receive(io, .{ .id = 0 }));
    mailbox.close(io);
    try std.testing.expectError(error.Closed, mailbox.deliver(io, 3));
    try std.testing.expectError(error.Closed, mailbox.receive(io, .init(1)));
}

test "nonblocking delivery retains rejected values and leaves no pending putter" {
    const io = std.testing.io;
    var storage: [1]u32 = undefined;
    var mailbox = Mailbox(u32).init(&storage);
    defer mailbox.close(io);
    try mailbox.tryDeliver(io, 11);
    try std.testing.expectError(error.WouldBlock, mailbox.tryDeliver(io, 22));
    try std.testing.expect(mailbox.queue.type_erased.putters.first == null);
    try std.testing.expectEqual(@as(u32, 11), try mailbox.receive(io, .init(1)));
    try mailbox.tryDeliver(io, 33);
    mailbox.close(io);
    try std.testing.expectError(error.Closed, mailbox.tryDeliver(io, 44));
    try std.testing.expectEqual(@as(u32, 33), try mailbox.receive(io, .init(1)));
    try std.testing.expectError(error.Closed, mailbox.receive(io, .init(1)));
    try std.testing.expect(mailbox.queue.type_erased.putters.first == null);
}

test "canceled nonblocking delivery transfers no element" {
    const io = std.testing.io;
    var storage: [1]u32 = undefined;
    var mailbox = Mailbox(u32).init(&storage);
    defer mailbox.close(io);
    const Sender = struct {
        started: std.Io.Event = .unset,
        mailbox: *Mailbox(u32),

        fn run(self: *@This()) !void {
            self.started.set(std.testing.io);
            try self.mailbox.tryDeliver(std.testing.io, 42);
        }
    };
    var sender = Sender{ .mailbox = &mailbox };
    mailbox.queue.type_erased.mutex.lockUncancelable(io);
    defer mailbox.queue.type_erased.mutex.unlock(io);
    var task = try io.concurrent(Sender.run, .{&sender});
    defer _ = task.cancel(io) catch {};
    try sender.started.wait(io);
    try std.testing.expectError(error.Canceled, task.cancel(io));
    try std.testing.expectEqual(@as(usize, 0), mailbox.queue.type_erased.len);
    try std.testing.expect(mailbox.queue.type_erased.putters.first == null);
}

test "copied consumer token cannot run two receives concurrently" {
    const io = std.testing.io;
    var storage: [1]u8 = undefined;
    var mailbox = Mailbox(u8).init(&storage);
    defer mailbox.close(io);
    const Consumer = struct {
        mailbox: *Mailbox(u8),
        failure: ?anyerror = null,
        fn run(self: *@This()) void {
            _ = self.mailbox.receive(std.testing.io, .init(1)) catch |err| {
                self.failure = err;
                return;
            };
        }
    };
    var consumer = Consumer{ .mailbox = &mailbox };
    var group: std.Io.Group = .init;
    defer group.cancel(io);
    try group.concurrent(io, Consumer.run, .{&consumer});
    var retries: usize = 0;
    while (!mailbox.receiving.load(.acquire)) {
        if (retries == 1000) return error.TestUnexpectedResult;
        retries += 1;
        try std.Io.sleep(io, .fromMilliseconds(1), .awake);
    }
    try std.testing.expectError(error.ConcurrentReceive, mailbox.receive(io, .init(1)));
    try mailbox.deliver(io, 42);
    try group.await(io);
    if (consumer.failure) |err| return err;
    try std.testing.expect(!mailbox.receiving.load(.acquire));
}
