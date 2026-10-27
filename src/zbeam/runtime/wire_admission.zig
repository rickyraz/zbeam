//! Internal single-reader reservation; caller owns the lease and must finish it
//! before runtime deinit. Lease values must not be copied or used concurrently.
const std = @import("std");
const Runtime = @import("task_runtime.zig");
const assert = std.debug.assert;

pub const Lease = struct {
    runtime: *Runtime,
    tickets: [2]?usize = @splat(null),
    active: bool = true,

    /// Roll back all untransferred reservations. Runtime storage must be live.
    pub fn release(self: *Lease) void {
        self.runtime.mutex.lockUncancelable(self.runtime.io);
        defer self.runtime.mutex.unlock(self.runtime.io);
        self.releaseLocked();
    }

    fn releaseLocked(self: *Lease) void {
        assert(self.active and self.runtime.wire_reservation_active);
        for (&self.tickets, &self.runtime.slots) |*ticket, *slot| {
            if (ticket.*) |value| {
                if (slot.ledger.records[value].stage == .reserved) {
                    slot.ledger.release(value);
                } else {
                    // Stop may retire a reservation while the reader is active.
                    assert(slot.state != .running);
                }
                ticket.* = null;
            }
        }
        self.runtime.wire_reservation_active = false;
        self.active = false;
    }

    /// Always consumes the lease, including on copy or insertion failure.
    /// Queue insertion is the acceptance point; failed input stays borrowed.
    pub fn send(self: *Lease, id: u64, bytes: []const u8) !u64 {
        const runtime = self.runtime;
        runtime.mutex.lockUncancelable(runtime.io);
        defer runtime.mutex.unlock(runtime.io);
        defer self.releaseLocked();
        if (id == 0 or id > 2) return error.ActorNotFound;
        const index: usize = @intCast(id - 1);
        const slot = &runtime.slots[index];
        if (slot.state != .running) return error.ActorStopped;
        const ticket = self.tickets[index] orelse return error.ActorStopped;
        if (runtime.next_id == 0) return error.RequestIdExhausted;
        const message = try slot.ledger.copyReserved(ticket, runtime.next_id, bytes);
        self.tickets[index] = null;
        slot.mailbox.tryDeliver(runtime.io, message) catch |err| {
            slot.ledger.undo(message);
            return err;
        };
        const accepted = runtime.next_id;
        runtime.next_id = if (accepted == std.math.maxInt(u64)) 0 else accepted + 1;
        return accepted;
    }
};

/// Reserves all currently running destinations atomically with local sends/stop.
/// The connection owner permits at most one lease and supplies output capacity
/// separately before reading. No I/O or payload allocation happens here.
pub fn acquire(runtime: *Runtime) !Lease {
    try runtime.mutex.lock(runtime.io);
    defer runtime.mutex.unlock(runtime.io);
    if (runtime.wire_reservation_active) return error.ReservationOutstanding;
    var lease = Lease{ .runtime = runtime };
    errdefer for (&lease.tickets, &runtime.slots) |ticket, *slot| {
        if (ticket) |value| slot.ledger.release(value);
    };
    for (&runtime.slots, &lease.tickets) |*slot, *ticket| {
        if (slot.state == .running) ticket.* = try slot.ledger.reserve();
    }
    runtime.wire_reservation_active = true;
    return lease;
}

const testing = std.testing;
const io = testing.io;

test "shared lease transfers exactly one destination and copies input" {
    var counted = testing.FailingAllocator.init(testing.allocator, .{});
    {
        const tasks = try Runtime.create(counted.allocator(), io, .{ "a", "b" });
        defer tasks.deinit() catch unreachable;
        defer _ = tasks.shutdown();
        const allocations = counted.alloc_index;
        var lease = try acquire(tasks);
        try testing.expectEqual(allocations, counted.alloc_index);
        try testing.expectError(error.ReservationOutstanding, acquire(tasks));
        var payload = [_]u8{ 'a', 'b', 'c' };
        const id = try lease.send(2, &payload);
        payload[0] = 'x';
        const result = (try tasks.nextResult()).?;
        try testing.expectEqual(id, result.request_id);
        try testing.expectEqual(@as(u64, 2), result.actor_id);
        try testing.expectEqualStrings("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", &std.fmt.bytesToHex(result.outcome.digest, .lower));
        var next = try acquire(tasks);
        next.release();
    }
    try testing.expectEqual(counted.allocated_bytes, counted.freed_bytes);
}

test "stop invalidates only its reservation; shutdown safely retires both" {
    const tasks = try Runtime.create(testing.allocator, io, .{ "a", "b" });
    defer tasks.deinit() catch unreachable;
    var lease = try acquire(tasks);
    try tasks.requestStop(1);
    try testing.expectError(error.ActorStopped, lease.send(1, "late"));
    var next = try acquire(tasks);
    try testing.expect(next.tickets[0] == null and next.tickets[1] != null);
    _ = tasks.shutdown();
    next.release();
    try testing.expect(try tasks.nextResult() == null);
}

test "retiring one destination preserves a sibling reservation" {
    const tasks = try Runtime.create(testing.allocator, io, .{ "a", "b" });
    defer tasks.deinit() catch unreachable;
    defer _ = tasks.shutdown();
    var lease = try acquire(tasks);
    try tasks.requestStop(1);
    const id = try lease.send(2, "abc");
    const result = (try tasks.nextResult()).?;
    try testing.expectEqual(id, result.request_id);
    try testing.expectEqual(@as(u64, 2), result.actor_id);
    try testing.expect(result.outcome == .digest);
}

test "shared reservation and local sends compete for the same queue positions" {
    const TestControl = @import("task_runtime_test.zig").Control;
    var control = TestControl{ .actor = 1 };
    const tasks = try Runtime.create(testing.allocator, io, .{ "a", "b" });
    defer tasks.deinit() catch unreachable;
    defer _ = tasks.shutdown();
    tasks.control = &control;
    _ = try tasks.trySend(2, "held");
    try control.entered.waitTimeout(io, .{ .duration = .{ .raw = .fromSeconds(5), .clock = .awake } });
    var lease = try acquire(tasks);
    for (0..3) |_| _ = try tasks.trySend(2, "queued");
    try testing.expectError(error.WouldBlock, tasks.trySend(2, "local overflow"));
    lease.release();
    _ = try tasks.trySend(2, "reused");
    control.release.set(io);
}

test "failed reserved copy releases all destinations" {
    var counted = testing.FailingAllocator.init(testing.allocator, .{});
    {
        const tasks = try Runtime.create(counted.allocator(), io, .{ "a", "b" });
        defer tasks.deinit() catch unreachable;
        defer _ = tasks.shutdown();
        var lease = try acquire(tasks);
        counted.fail_index = counted.alloc_index;
        try testing.expectError(error.OutOfMemory, lease.send(1, "abc"));
        counted.fail_index = std.math.maxInt(usize);
        var next = try acquire(tasks);
        next.release();
        _ = try tasks.trySend(1, "ok");
        _ = (try tasks.nextResult()).?;
    }
    try testing.expectEqual(counted.allocated_bytes, counted.freed_bytes);
}

test "canceled insertion destroys the copy and releases both reservations" {
    var counted = testing.FailingAllocator.init(testing.allocator, .{});
    {
        const tasks = try Runtime.create(counted.allocator(), io, .{ "a", "b" });
        defer tasks.deinit() catch unreachable;
        defer _ = tasks.shutdown();
        var lease = try acquire(tasks);
        const Sender = struct {
            lease: *Lease,
            started: std.Io.Event = .unset,
            fn run(self: *@This()) !u64 {
                self.started.set(io);
                return self.lease.send(1, "abc");
            }
        };
        var sender = Sender{ .lease = &lease };
        const result = canceled: {
            tasks.slots[0].mailbox.queue.type_erased.mutex.lockUncancelable(io);
            defer tasks.slots[0].mailbox.queue.type_erased.mutex.unlock(io);
            var future = try io.concurrent(Sender.run, .{&sender});
            defer _ = future.cancel(io) catch 0;
            try sender.started.wait(io);
            break :canceled future.cancel(io);
        };
        try testing.expectError(error.Canceled, result);
        try testing.expectEqual(@sizeOf(Runtime), counted.allocated_bytes - counted.freed_bytes);
        var next = try acquire(tasks);
        next.release();
    }
    try testing.expectEqual(counted.allocated_bytes, counted.freed_bytes);
}

test "second-destination full rolls first reservation back atomically" {
    const TestControl = @import("task_runtime_test.zig").Control;
    var control = TestControl{ .actor = 1 };
    const tasks = try Runtime.create(testing.allocator, io, .{ "a", "b" });
    defer tasks.deinit() catch unreachable;
    defer _ = tasks.shutdown();
    tasks.control = &control;
    _ = try tasks.trySend(2, "held");
    try control.entered.waitTimeout(io, .{ .duration = .{ .raw = .fromSeconds(5), .clock = .awake } });
    for (0..4) |_| _ = try tasks.trySend(2, "queued");
    try testing.expectError(error.WouldBlock, acquire(tasks));
    {
        tasks.mutex.lockUncancelable(io);
        defer tasks.mutex.unlock(io);
        for (tasks.slots[0].ledger.records) |record| try testing.expect(record.stage == .free);
        try testing.expect(!tasks.wire_reservation_active);
    }
    control.release.set(io);
}
