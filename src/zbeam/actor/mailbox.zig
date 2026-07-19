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

        /// Enforces one logical actor token as the mailbox consumer.
        pub fn receive(self: *Self, io: std.Io, token: Token) !Message {
            try self.claim(token);
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
}
