//! Two fixed local SHA-256 actors. The owner must join API users before deinit;
//! stop/cancel joins cooperatively, never preempts CPU code or isolates a panic.
const std = @import("std");
const builtin = @import("builtin");
const actor = @import("zbeam-actor");
const admission = @import("task_admission.zig");
const Self = @This();

pub const Outcome = admission.Outcome;
pub const Result = struct { actor_id: u64, request_id: u64, outcome: Outcome };
pub const Exit = enum { stopped, canceled, handler_failed };
const State = enum { starting, running, stopping, exited, joined };
const Slot = struct {
    name: [64]u8 = undefined,
    name_len: usize,
    state: State = .starting,
    storage: [admission.queue_capacity]admission.Message = undefined,
    mailbox: actor.Mailbox(admission.Message) = undefined,
    ledger: admission.Admission,
    ready: std.Io.Event = .unset,
    future: ?std.Io.Future(void) = null,
    exit: Exit = .stopped,
};

allocator: std.mem.Allocator,
io: std.Io,
mutex: std.Io.Mutex = .init,
changed: std.Io.Condition = .init,
start: std.Io.Event = .unset,
slots: [2]Slot = undefined,
next_id: u64 = 1,
joined: bool = false,
control: if (builtin.is_test) ?*@import("task_runtime_test.zig").Control else void = if (builtin.is_test) null else {},

/// Allocates stable storage and publishes neither identity until both tasks are
/// ready. Allocator and I/O provider must outlive the joined runtime and support
/// concurrent use. Start/shutdown/stopAndJoin/deinit have one lifecycle owner.
pub fn create(allocator: std.mem.Allocator, io: std.Io, names: [2][]const u8) !*Self {
    for (names) |name| if (name.len == 0 or name.len > 64) return error.InvalidName;
    if (std.mem.eql(u8, names[0], names[1])) return error.NameTaken;
    const self = try allocator.create(Self);
    errdefer allocator.destroy(self);
    self.* = .{ .allocator = allocator, .io = io };
    for (&self.slots, names) |*slot, name| {
        slot.* = .{ .name_len = name.len, .ledger = .{ .allocator = allocator } };
        @memcpy(slot.name[0..name.len], name);
        slot.mailbox = .init(&slot.storage);
    }
    errdefer _ = self.shutdown();
    for (&self.slots, 0..) |*slot, i| slot.future = try io.concurrent(run, .{ self, i });
    for (&self.slots) |*slot| try slot.ready.wait(io);
    for (&self.slots) |*slot| slot.state = .running;
    self.start.set(io);
    return self;
}

/// Requires shutdown/joins AND caller-established quiescence of all API users.
/// Refuses early destruction rather than silently detaching live tasks.
pub fn deinit(self: *Self) !void {
    if (!self.joined) return error.NotJoined;
    for (&self.slots) |*slot| slot.ledger.discard();
    self.allocator.destroy(self);
}

pub fn whereis(self: *Self, name: []const u8) ?u64 {
    self.mutex.lockUncancelable(self.io);
    defer self.mutex.unlock(self.io);
    for (&self.slots, 0..) |*slot, i| {
        if (slot.state == .running and std.mem.eql(u8, slot.name[0..slot.name_len], name)) return i + 1;
    }
    return null;
}

/// Copies at most 1 MiB under the admission gate; never waits for queue space.
/// IDs are scoped to this live instance, not ETF PIDs or persistent identities.
pub fn trySend(self: *Self, id: u64, bytes: []const u8) !u64 {
    const i = try index(id);
    try self.mutex.lock(self.io);
    defer self.mutex.unlock(self.io);
    const slot = &self.slots[i];
    if (slot.state != .running) return error.ActorStopped;
    if (self.next_id == 0) return error.RequestIdExhausted;
    const message = try slot.ledger.copy(self.next_id, bytes);
    slot.mailbox.tryDeliver(self.io, message) catch |err| {
        slot.ledger.undo(message);
        return err;
    };
    const accepted = self.next_id;
    self.next_id = if (accepted == std.math.maxInt(u64)) 0 else accepted + 1;
    return accepted;
}

/// One collector; terminal records remain inline until collected or deinit.
/// Returns null only after all tasks joined, queues drained and results consumed.
pub fn nextResult(self: *Self) !?Result {
    try self.mutex.lock(self.io);
    defer self.mutex.unlock(self.io);
    while (true) {
        for (&self.slots, 0..) |*slot, i| {
            if (slot.ledger.take()) |result| return .{ .actor_id = i + 1, .request_id = result.request_id, .outcome = result.outcome };
        }
        if (self.joined) return null;
        try self.changed.wait(self.io, &self.mutex);
    }
}

pub fn requestStop(self: *Self, id: u64) !void {
    const i = try index(id);
    self.mutex.lockUncancelable(self.io);
    defer self.mutex.unlock(self.io);
    self.stopLocked(i);
}

pub fn stopAndJoin(self: *Self, id: u64) !Exit {
    const i = try index(id);
    try self.requestStop(id);
    self.joinSlot(i);
    return self.slots[i].exit;
}

/// Stop both before joining either. Cleanup cannot be skipped by cancellation;
/// a noncooperative handler still requires external process termination.
pub fn shutdown(self: *Self) [2]Exit {
    self.mutex.lockUncancelable(self.io);
    for (0..2) |i| self.stopLocked(i);
    self.mutex.unlock(self.io);
    self.start.set(self.io);
    for (0..2) |i| self.joinSlot(i);
    return .{ self.slots[0].exit, self.slots[1].exit };
}

fn index(id: u64) !usize {
    if (id == 0 or id > 2) return error.ActorNotFound;
    return @intCast(id - 1);
}

fn stopLocked(self: *Self, i: usize) void {
    const slot = &self.slots[i];
    if (slot.state == .starting or slot.state == .running) slot.state = .stopping;
    slot.mailbox.close(self.io);
    if (builtin.is_test) {
        if (self.control) |control| if (control.actor == i) control.release.set(self.io);
    }
}

fn run(self: *Self, i: usize) void {
    const slot = &self.slots[i];
    slot.ready.set(self.io);
    const exit: Exit = if (self.work(i)) |_| .stopped else |err| switch (err) {
        error.Canceled => .canceled,
        error.HandlerFailed => .handler_failed,
    };
    self.mutex.lockUncancelable(self.io);
    defer self.mutex.unlock(self.io);
    slot.exit = exit;
    slot.state = .exited;
    slot.mailbox.close(self.io);
    self.changed.broadcast(self.io);
}

fn work(self: *Self, i: usize) error{ Canceled, HandlerFailed }!void {
    try self.start.wait(self.io);
    while (true) {
        try self.io.checkCancel();
        const message = self.slots[i].mailbox.receive(self.io, .init(i + 1)) catch |err| switch (err) {
            error.Closed => return,
            error.Canceled => return error.Canceled,
            else => unreachable,
        };
        try self.process(i, message);
    }
}

fn process(self: *Self, i: usize, message: admission.Message) !void {
    var outcome: Outcome = .stopped;
    var claimed = false;
    defer self.complete(i, message, outcome, claimed);
    if (builtin.is_test) {
        if (self.control) |control| control.checkpoint(self.io, i, .before_claim) catch |err| {
            outcome = if (err == error.Canceled) .canceled else .handler_failed;
            return err;
        };
    }
    self.mutex.lockUncancelable(self.io);
    self.slots[i].ledger.claim(message);
    claimed = true;
    const running = self.slots[i].state == .running;
    self.mutex.unlock(self.io);
    if (!running) return;
    if (builtin.is_test) {
        if (self.control) |control| control.checkpoint(self.io, i, .active) catch |err| {
            outcome = if (err == error.Canceled) .canceled else .handler_failed;
            return err;
        };
    }
    self.io.checkCancel() catch |err| {
        outcome = .canceled;
        return err;
    };
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(message.bytes, &digest, .{});
    outcome = .{ .digest = digest };
}

fn complete(self: *Self, i: usize, message: admission.Message, outcome: Outcome, claimed: bool) void {
    self.mutex.lockUncancelable(self.io);
    defer self.mutex.unlock(self.io);
    if (!claimed) self.slots[i].ledger.claim(message);
    self.slots[i].ledger.finish(message, outcome);
    self.changed.broadcast(self.io);
}

fn joinSlot(self: *Self, i: usize) void {
    const slot = &self.slots[i];
    if (slot.future) |*future| future.cancel(self.io);
    const previous = self.io.swapCancelProtection(.blocked);
    defer _ = self.io.swapCancelProtection(previous);
    while (true) {
        const message = slot.mailbox.receive(self.io, .init(i + 1)) catch |err| switch (err) {
            error.Closed => break,
            else => unreachable,
        };
        self.mutex.lockUncancelable(self.io);
        slot.ledger.claim(message);
        self.mutex.unlock(self.io);
        self.complete(i, message, .stopped, true);
    }
    self.mutex.lockUncancelable(self.io);
    defer self.mutex.unlock(self.io);
    slot.state = .joined;
    self.joined = self.slots[0].state == .joined and self.slots[1].state == .joined;
    self.changed.broadcast(self.io);
}

test {
    _ = @import("task_runtime_test.zig");
}

test "task owner copies names, hashes on both actors, stops and joins idempotently" {
    var name = [_]u8{'a'};
    const self = try create(std.testing.allocator, std.testing.io, .{ &name, "b" });
    name[0] = 'x';
    defer self.deinit() catch unreachable;
    defer _ = self.shutdown();
    try std.testing.expectError(error.NotJoined, self.deinit());
    const a = self.whereis("a").?;
    const b = self.whereis("b").?;
    const first = try self.trySend(a, "abc");
    const second = try self.trySend(b, "abc");
    var seen: [2]bool = @splat(false);
    for (0..2) |_| {
        const result = (try self.nextResult()).?;
        try std.testing.expect(result.request_id == first or result.request_id == second);
        try std.testing.expect(!seen[result.actor_id - 1]);
        seen[result.actor_id - 1] = true;
        try std.testing.expectEqualStrings("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", &std.fmt.bytesToHex(result.outcome.digest, .lower));
    }
    _ = try self.stopAndJoin(a);
    try std.testing.expect(self.whereis("a") == null);
    try std.testing.expectError(error.ActorStopped, self.trySend(a, "abc"));
    _ = self.shutdown();
    const again = self.shutdown();
    try std.testing.expectEqual(again[0], try self.stopAndJoin(a));
    try std.testing.expect(try self.nextResult() == null);
}

test "invalid names and runtime allocation failure publish no actors" {
    try std.testing.expectError(error.InvalidName, create(std.testing.allocator, std.testing.io, .{ "", "b" }));
    try std.testing.expectError(error.NameTaken, create(std.testing.allocator, std.testing.io, .{ "a", "a" }));
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectError(error.OutOfMemory, create(failing.allocator(), std.testing.io, .{ "a", "b" }));
}

test "first or second task start failure joins all started tasks before freeing" {
    const Shim = struct {
        var calls: usize = 0;
        var reject: usize = 0;
        var joins: usize = 0;

        fn concurrent(userdata: ?*anyopaque, len: usize, alignment: std.mem.Alignment, context: []const u8, context_alignment: std.mem.Alignment, entry: *const fn (*const anyopaque, *anyopaque) void) std.Io.ConcurrentError!*std.Io.AnyFuture {
            calls += 1;
            if (calls == reject) return error.ConcurrencyUnavailable;
            return std.testing.io.vtable.concurrent(userdata, len, alignment, context, context_alignment, entry);
        }

        fn cancel(userdata: ?*anyopaque, future: *std.Io.AnyFuture, result: []u8, alignment: std.mem.Alignment) void {
            std.testing.io.vtable.cancel(userdata, future, result, alignment);
            joins += 1;
        }
    };
    var vtable = std.testing.io.vtable.*;
    vtable.concurrent = Shim.concurrent;
    vtable.cancel = Shim.cancel;
    const io = std.Io{ .userdata = std.testing.io.userdata, .vtable = &vtable };
    for (1..3) |reject| {
        Shim.calls = 0;
        Shim.joins = 0;
        Shim.reject = reject;
        var counted = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        try std.testing.expectError(error.ConcurrencyUnavailable, create(counted.allocator(), io, .{ "a", "b" }));
        try std.testing.expectEqual(reject - 1, Shim.joins);
        try std.testing.expectEqual(counted.allocated_bytes, counted.freed_bytes);
    }
}
