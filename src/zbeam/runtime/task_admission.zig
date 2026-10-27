//! Internal per-actor ownership ledger. Every operation requires the runtime's
//! lifecycle mutex; this type does not schedule tasks or implement a mailbox.
const std = @import("std");
const assert = std.debug.assert;

pub const max_input = 1024 * 1024;
pub const queue_capacity = 4;
pub const ticket_capacity = queue_capacity + 1;
pub const Outcome = union(enum) { digest: [32]u8, stopped, canceled, handler_failed };
pub const Completion = struct { request_id: u64, outcome: Outcome };
pub const Message = struct { ticket: usize, bytes: []u8 };

pub const Admission = struct {
    const Stage = enum { free, reserved, queued, active, complete };
    const Record = struct {
        stage: Stage = .free,
        id: u64 = 0,
        outcome: Outcome = .stopped,
    };

    allocator: std.mem.Allocator,
    records: [ticket_capacity]Record = @splat(.{}),

    /// Reserve one logical queue position and completion ticket without allocating.
    /// The caller holds the lifecycle mutex and must consume or release it.
    pub fn reserve(self: *Admission) error{WouldBlock}!usize {
        var queued: usize = 0;
        var available: ?usize = null;
        for (self.records, 0..) |record, i| {
            if (record.stage == .queued or record.stage == .reserved) queued += 1;
            if (record.stage == .free) available = i;
        }
        if (queued == queue_capacity) return error.WouldBlock;
        const ticket = available orelse return error.WouldBlock;
        self.records[ticket].stage = .reserved;
        return ticket;
    }

    pub fn release(self: *Admission, ticket: usize) void {
        assert(self.records[ticket].stage == .reserved);
        self.records[ticket] = .{};
    }

    /// Allocation failure leaves the reservation owned by the caller.
    pub fn copyReserved(self: *Admission, ticket: usize, id: u64, borrowed: []const u8) !Message {
        assert(self.records[ticket].stage == .reserved);
        if (borrowed.len > max_input) return error.InputTooLarge;
        assert(id != 0);
        for (self.records) |record| assert(record.stage == .free or record.stage == .reserved or record.id != id);
        const bytes = try self.allocator.dupe(u8, borrowed);
        self.records[ticket] = .{ .stage = .queued, .id = id };
        return .{ .ticket = ticket, .bytes = bytes };
    }

    /// Reserve both a logical queue position and a completion ticket before
    /// copying. Failure changes neither ownership nor admission capacity.
    pub fn copy(self: *Admission, id: u64, borrowed: []const u8) !Message {
        if (borrowed.len > max_input) return error.InputTooLarge;
        const ticket = try self.reserve();
        errdefer self.release(ticket);
        return self.copyReserved(ticket, id, borrowed);
    }

    /// Called only when queue insertion failed without transferring the element.
    pub fn undo(self: *Admission, message: Message) void {
        assert(self.records[message.ticket].stage == .queued);
        self.allocator.free(message.bytes);
        self.records[message.ticket] = .{};
    }

    /// Transfers a dequeued value to the sole consumer, even on the stop path.
    pub fn claim(self: *Admission, message: Message) void {
        assert(self.records[message.ticket].stage == .queued);
        self.records[message.ticket].stage = .active;
    }

    /// No allocation or wait: the ticket already reserves terminal-result space.
    pub fn finish(self: *Admission, message: Message, outcome: Outcome) void {
        const record = &self.records[message.ticket];
        assert(record.stage == .active);
        self.allocator.free(message.bytes);
        record.stage = .complete;
        record.outcome = outcome;
    }

    /// Result collection, not payload destruction, returns outstanding capacity.
    pub fn take(self: *Admission) ?Completion {
        for (&self.records) |*record| {
            if (record.stage != .complete) continue;
            const completion = Completion{ .request_id = record.id, .outcome = record.outcome };
            record.* = .{};
            return completion;
        }
        return null;
    }

    /// Only after task join and queue drain; queued/active payloads must not leak.
    pub fn discard(self: *Admission) void {
        for (&self.records) |*record| {
            assert(record.stage == .free or record.stage == .complete);
            record.* = .{};
        }
    }
};

test "reservations consume queue and ticket capacity without allocating" {
    var counted = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var admission = Admission{ .allocator = counted.allocator() };
    var tickets: [queue_capacity]usize = undefined;
    for (&tickets) |*ticket| ticket.* = try admission.reserve();
    try std.testing.expectError(error.WouldBlock, admission.reserve());
    try std.testing.expectError(error.WouldBlock, admission.copy(1, "no allocation"));
    try std.testing.expectEqual(@as(usize, 0), counted.alloc_index);
    admission.release(tickets[0]);
    const message = try admission.copy(1, "abc");
    try std.testing.expectError(error.WouldBlock, admission.reserve());
    for (tickets[1..]) |ticket| admission.release(ticket);
    admission.claim(message);
    admission.finish(message, .stopped);
    try std.testing.expectEqual(@as(u64, 1), admission.take().?.request_id);
    admission.discard();
    try std.testing.expectEqual(counted.allocated_bytes, counted.freed_bytes);
}

test "reserved copy failure retains its reservation until explicit release" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var admission = Admission{ .allocator = failing.allocator() };
    const ticket = try admission.reserve();
    try std.testing.expectError(error.OutOfMemory, admission.copyReserved(ticket, 1, "abc"));
    const oversized = try std.testing.allocator.alloc(u8, max_input + 1);
    defer std.testing.allocator.free(oversized);
    try std.testing.expectError(error.InputTooLarge, admission.copyReserved(ticket, 1, oversized));
    try std.testing.expect(admission.records[ticket].stage == .reserved);
    admission.release(ticket);
    failing.fail_index = std.math.maxInt(usize);
    var borrowed = [_]u8{ 1, 2, 3 };
    const next = try admission.reserve();
    const message = try admission.copyReserved(next, 2, &borrowed);
    borrowed[0] = 42;
    try std.testing.expectEqual(@as(u8, 1), message.bytes[0]);
    admission.undo(message);
    admission.discard();
    try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
}

test "admission copies before transfer and rolls back without retaining capacity" {
    var counted = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var admission = Admission{ .allocator = counted.allocator() };
    var borrowed = [_]u8{ 1, 2, 3 };
    const message = try admission.copy(1, &borrowed);
    borrowed[0] = 99;
    try std.testing.expectEqual(@as(u8, 1), message.bytes[0]);
    admission.undo(message);
    try std.testing.expectEqual(counted.allocated_bytes, counted.freed_bytes);
    const next = try admission.copy(2, &borrowed);
    admission.claim(next);
    admission.finish(next, .canceled);
    const completion = admission.take().?;
    try std.testing.expectEqual(@as(u64, 2), completion.request_id);
    try std.testing.expect(completion.outcome == .canceled);
    try std.testing.expect(admission.take() == null);
    admission.discard();
    try std.testing.expectEqual(counted.allocated_bytes, counted.freed_bytes);
}

test "four queue positions and five completion-held tickets bound owned input" {
    var counted = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var admission = Admission{ .allocator = counted.allocator() };
    const input = try std.testing.allocator.alloc(u8, max_input);
    defer std.testing.allocator.free(input);
    @memset(input, 0x5a);
    var messages: [ticket_capacity]Message = undefined;
    for (messages[0..queue_capacity], 0..) |*message, i| message.* = try admission.copy(i + 1, input);
    try std.testing.expectError(error.WouldBlock, admission.copy(99, input));
    admission.claim(messages[0]);
    messages[4] = try admission.copy(5, input);
    try std.testing.expectEqual(@as(usize, 5 * max_input), counted.allocated_bytes - counted.freed_bytes);
    admission.finish(messages[0], .{ .digest = @splat(42) });
    for (messages[1..]) |message| {
        admission.claim(message);
        admission.finish(message, .stopped);
    }
    try std.testing.expectEqual(counted.allocated_bytes, counted.freed_bytes);
    const attempts = counted.alloc_index;
    try std.testing.expectError(error.WouldBlock, admission.copy(99, input));
    try std.testing.expectEqual(attempts, counted.alloc_index);
    var seen: [ticket_capacity]bool = @splat(false);
    while (admission.take()) |completion| {
        const i = completion.request_id - 1;
        try std.testing.expect(!seen[i]);
        seen[i] = true;
        if (i == 0) try std.testing.expectEqual(@as([32]u8, @splat(42)), completion.outcome.digest);
    }
    for (seen) |present| try std.testing.expect(present);
    admission.undo(try admission.copy(100, input));
    admission.discard();
    try std.testing.expectEqual(counted.allocated_bytes, counted.freed_bytes);
}

test "failed allocation and oversized input leave every reservation reusable" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var admission = Admission{ .allocator = failing.allocator() };
    try std.testing.expectError(error.OutOfMemory, admission.copy(1, "abc"));
    const oversized = try std.testing.allocator.alloc(u8, max_input + 1);
    defer std.testing.allocator.free(oversized);
    try std.testing.expectError(error.InputTooLarge, admission.copy(1, oversized));
    failing.fail_index = std.math.maxInt(usize);
    var messages: [queue_capacity]Message = undefined;
    for (&messages, 0..) |*message, i| message.* = try admission.copy(i + 1, "abc");
    for (messages) |message| admission.undo(message);
    admission.discard();
    try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
}
