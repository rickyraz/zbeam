//! Internal connection-scoped correlation credits. Every operation requires
//! the connection gate; the authenticated peer name must outlive this table.
const std = @import("std");
const etf = @import("zbeam-etf");
const assert = std.debug.assert;

pub const capacity = 10;
const Stage = enum { free, reserved, prepared, pending, writing };
const Entry = struct {
    stage: Stage = .free,
    id: u64 = 0,
    to: etf.Pid = undefined,
    reference: etf.Reference = undefined,
};

pub const Table = struct {
    peer_name: []const u8,
    peer_creation: u32,
    epoch: u64,
    entries: [capacity]Entry = @splat(.{}),

    /// Reserves one output credit before reading; no allocation or waiting.
    pub fn reserve(self: *Table) error{WouldBlock}!usize {
        for (&self.entries, 0..) |*entry, i| {
            if (entry.stage != .free) continue;
            entry.stage = .reserved;
            return i;
        }
        return error.WouldBlock;
    }

    /// Validate before accepting work; keep only the canonical peer-owned node.
    pub fn prepare(self: *Table, ticket: usize, to: etf.Pid, reference: etf.Reference) !void {
        const entry = &self.entries[ticket];
        assert(entry.stage == .reserved);
        if (to.creation != self.peer_creation or reference.creation != self.peer_creation or
            !std.mem.eql(u8, to.node, self.peer_name) or !std.mem.eql(u8, reference.node, self.peer_name)) return error.UnexpectedPeer;
        if (reference.len == 0 or reference.len > reference.ids.len) return error.InvalidReference;
        entry.to = to;
        entry.to.node = self.peer_name;
        entry.reference = reference;
        entry.reference.node = self.peer_name;
        entry.stage = .prepared;
    }

    /// Must be called under the gate immediately after successful admission;
    /// request IDs are unique and nonzero within the live task runtime.
    pub fn bind(self: *Table, ticket: usize, id: u64) void {
        const entry = &self.entries[ticket];
        assert(entry.stage == .prepared and id != 0);
        for (self.entries) |other| assert(other.stage != .pending and other.stage != .writing or other.id != id);
        entry.id = id;
        entry.stage = .pending;
    }

    pub fn cancel(self: *Table, ticket: usize) void {
        const entry = &self.entries[ticket];
        assert(entry.stage == .reserved or entry.stage == .prepared);
        entry.* = .{};
    }

    pub const Delivery = struct { ticket: usize, to: etf.Pid, reference: etf.Reference };

    /// A matching completion moves to writing, but does not free its credit.
    pub fn beginWrite(self: *Table, epoch: u64, id: u64) ?Delivery {
        if (epoch != self.epoch) return null;
        for (&self.entries, 0..) |*entry, i| {
            if (entry.stage != .pending or entry.id != id) continue;
            entry.stage = .writing;
            return .{ .ticket = i, .to = entry.to, .reference = entry.reference };
        }
        return null;
    }

    /// Called after the owned writer finishes or drops this particular output.
    pub fn finishWrite(self: *Table, ticket: usize) void {
        assert(self.entries[ticket].stage == .writing);
        self.entries[ticket] = .{};
    }

    /// Only after the reader and writer are joined and pending results drained.
    pub fn discard(self: *Table) void {
        for (&self.entries) |*entry| {
            assert(entry.stage != .writing);
            entry.* = .{};
        }
    }
};

const testing = std.testing;
const peer = "peer@host";
const pid = etf.Pid{ .node = peer, .id = 4, .serial = 5, .creation = 7 };
const test_reference = etf.Reference{ .node = peer, .creation = 7, .ids = .{ 1, 2, 3, 4, 5 }, .len = 5 };

test "output credit persists from reserve through actual write completion" {
    var table = Table{ .peer_name = peer, .peer_creation = 7, .epoch = 1 };
    var tickets: [capacity]usize = undefined;
    for (&tickets, 0..) |*ticket, i| {
        ticket.* = try table.reserve();
        try table.prepare(ticket.*, pid, test_reference);
        table.bind(ticket.*, i + 1);
    }
    try testing.expectError(error.WouldBlock, table.reserve());
    const delivery = table.beginWrite(1, 1).?;
    try testing.expect(delivery.to.eql(pid) and delivery.reference.eql(test_reference));
    try testing.expectError(error.WouldBlock, table.reserve());
    table.finishWrite(delivery.ticket);
    const reused = try table.reserve();
    table.cancel(reused);
    table.discard();
}

test "epoch fences stale and unknown completions without returning credit" {
    var table = Table{ .peer_name = peer, .peer_creation = 7, .epoch = 2 };
    const ticket = try table.reserve();
    try table.prepare(ticket, pid, test_reference);
    table.bind(ticket, 99);
    try testing.expect(table.beginWrite(1, 99) == null);
    try testing.expect(table.beginWrite(2, 100) == null);
    try testing.expectEqual(Stage.pending, table.entries[ticket].stage);
    table.finishWrite(table.beginWrite(2, 99).?.ticket);
    table.discard();
}

test "peer validation and cleanup precede acceptance" {
    var name = [_]u8{ 'p', 'e', 'e', 'r', '@', 'h', 'o', 's', 't' };
    var table = Table{ .peer_name = peer, .peer_creation = 7, .epoch = 3 };
    const ticket = try table.reserve();
    var invalid = pid;
    invalid.creation = 8;
    try testing.expectError(error.UnexpectedPeer, table.prepare(ticket, invalid, test_reference));
    invalid = pid;
    invalid.node = &name;
    var borrowed_reference = test_reference;
    borrowed_reference.node = &name;
    try table.prepare(ticket, invalid, borrowed_reference);
    name[0] = 'x';
    table.bind(ticket, 1);
    const delivery = table.beginWrite(3, 1).?;
    try testing.expectEqualStrings(peer, delivery.to.node);
    try testing.expectEqualStrings(peer, delivery.reference.node);
    table.finishWrite(delivery.ticket);
    const next = try table.reserve();
    var bad_ref = test_reference;
    bad_ref.len = 0;
    try testing.expectError(error.InvalidReference, table.prepare(next, pid, bad_ref));
    bad_ref = test_reference;
    bad_ref.creation = 8;
    try testing.expectError(error.UnexpectedPeer, table.prepare(next, pid, bad_ref));
    table.cancel(next);
    table.discard();
}
