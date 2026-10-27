//! Imported only by test builds; no fault switch or pause hook exists in production.
const std = @import("std");
const Runtime = @import("task_runtime.zig");
const io = std.testing.io;

const Phase = enum { before_claim, active };
pub const Control = struct {
    actor: usize = 0,
    phase: Phase = .active,
    entered: std.Io.Event = .unset,
    release: std.Io.Event = .unset,
    active_entries: std.atomic.Value(usize) = .init(0),
    fail: bool = false,

    pub fn checkpoint(self: *@This(), context: std.Io, actor: usize, phase: Phase) !void {
        if (actor != self.actor) return;
        if (phase == .active) _ = self.active_entries.fetchAdd(1, .monotonic);
        if (phase != self.phase) return;
        self.entered.set(context);
        try self.release.wait(context);
        if (self.fail) return error.HandlerFailed;
    }
};

fn waitEntered(control: *Control) !void {
    const deadline = (std.Io.Timeout{ .duration = .{ .raw = .fromSeconds(5), .clock = .awake } }).toDeadline(io);
    while (!control.entered.isSet()) {
        control.entered.waitTimeout(io, deadline) catch |err| switch (err) {
            error.Timeout => if (deadline.deadline.untilNow(io).raw.nanoseconds >= 0) return err,
            else => return err,
        };
    }
}

fn completed(tasks: *Runtime, actor: usize, count: usize) !void {
    const deadline = (std.Io.Timeout{ .duration = .{ .raw = .fromSeconds(5), .clock = .awake } }).toDeadline(io);
    tasks.mutex.lockUncancelable(io);
    defer tasks.mutex.unlock(io);
    while (true) {
        var ready: usize = 0;
        for (tasks.slots[actor].ledger.records) |record| {
            if (record.stage == .complete) ready += 1;
        }
        if (ready == count) return;
        try tasks.changed.waitTimeout(io, &tasks.mutex, deadline);
    }
}

test "lifecycle: stop wins after dequeue but before handler claim" {
    var counted = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    {
        var control = Control{ .phase = .before_claim };
        const tasks = try Runtime.create(counted.allocator(), io, .{ "a", "b" });
        defer tasks.deinit() catch unreachable;
        defer _ = tasks.shutdown();
        tasks.control = &control;
        for (0..4) |i| {
            _ = try tasks.trySend(1, "owned");
            if (i == 0) try waitEntered(&control);
        }
        const attempts = counted.alloc_index;
        try std.testing.expectError(error.WouldBlock, tasks.trySend(1, "overflow"));
        try std.testing.expectEqual(attempts, counted.alloc_index);
        try tasks.requestStop(1);
        try std.testing.expectError(error.ActorStopped, tasks.trySend(1, "late"));
        _ = tasks.shutdown();
        var count: usize = 0;
        var seen: [4]bool = @splat(false);
        while (try tasks.nextResult()) |result| {
            try std.testing.expect(result.outcome == .stopped or result.outcome == .canceled);
            try std.testing.expect(!seen[result.request_id - 1]);
            seen[result.request_id - 1] = true;
            count += 1;
        }
        try std.testing.expectEqual(@as(usize, 4), count);
        try std.testing.expectEqual(@as(usize, 0), control.active_entries.load(.monotonic));
    }
    try std.testing.expectEqual(counted.allocated_bytes, counted.freed_bytes);
}

test "lifecycle: cancellation after dequeue cleans before any handler claim" {
    var control = Control{ .phase = .before_claim };
    const tasks = try Runtime.create(std.testing.allocator, io, .{ "a", "b" });
    defer tasks.deinit() catch unreachable;
    defer _ = tasks.shutdown();
    tasks.control = &control;
    _ = try tasks.trySend(1, "owned");
    try waitEntered(&control);
    tasks.slots[0].future.?.cancel(io);
    try std.testing.expectEqual(Runtime.Exit.canceled, try tasks.stopAndJoin(1));
    _ = tasks.shutdown();
    const result = (try tasks.nextResult()).?;
    try std.testing.expect(result.outcome == .canceled);
    try std.testing.expect(try tasks.nextResult() == null);
    try std.testing.expectEqual(@as(usize, 0), control.active_entries.load(.monotonic));
}

test "lifecycle: paused actor retains bounded input while sibling completes 100 jobs" {
    var counted = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    {
        var control: Control = .{};
        const tasks = try Runtime.create(counted.allocator(), io, .{ "a", "b" });
        defer tasks.deinit() catch unreachable;
        defer _ = tasks.shutdown();
        tasks.control = &control;
        _ = try tasks.trySend(1, "held");
        try waitEntered(&control);
        for (0..4) |_| _ = try tasks.trySend(1, "queued");
        try std.testing.expectError(error.WouldBlock, tasks.trySend(1, "overflow"));
        for (0..100) |_| {
            const request = try tasks.trySend(2, "abc");
            const result = (try tasks.nextResult()).?;
            try std.testing.expectEqual(@as(u64, 2), result.actor_id);
            try std.testing.expectEqual(request, result.request_id);
            try std.testing.expectEqualStrings("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", &std.fmt.bytesToHex(result.outcome.digest, .lower));
        }
        _ = tasks.shutdown();
        var count: usize = 0;
        while (try tasks.nextResult()) |_| count += 1;
        try std.testing.expectEqual(@as(usize, 5), count);
        try std.testing.expectEqual(@as(usize, 1), control.active_entries.load(.monotonic));
    }
    try std.testing.expectEqual(counted.allocated_bytes, counted.freed_bytes);
}

test "lifecycle: ten uncollected results backpressure without retained payloads" {
    var counted = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    {
        const tasks = try Runtime.create(counted.allocator(), io, .{ "a", "b" });
        defer tasks.deinit() catch unreachable;
        defer _ = tasks.shutdown();
        for (0..2) |actor| for (0..5) |i| {
            _ = try tasks.trySend(actor + 1, "abc");
            try completed(tasks, actor, i + 1);
        };
        const attempts = counted.alloc_index;
        try std.testing.expectError(error.WouldBlock, tasks.trySend(1, "abc"));
        try std.testing.expectError(error.WouldBlock, tasks.trySend(2, "abc"));
        try std.testing.expectEqual(attempts, counted.alloc_index);
        try std.testing.expectEqual(@sizeOf(Runtime), counted.allocated_bytes - counted.freed_bytes);
        const collected = (try tasks.nextResult()).?;
        _ = try tasks.trySend(collected.actor_id, "reused ticket");
        _ = tasks.shutdown();
        var count: usize = 1;
        while (try tasks.nextResult()) |_| count += 1;
        try std.testing.expectEqual(@as(usize, 11), count);
    }
    try std.testing.expectEqual(counted.allocated_bytes, counted.freed_bytes);
}

test "lifecycle: deinit explicitly discards a retained inline completion" {
    var counted = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    {
        const tasks = try Runtime.create(counted.allocator(), io, .{ "a", "b" });
        defer tasks.deinit() catch unreachable;
        defer _ = tasks.shutdown();
        _ = try tasks.trySend(1, "discard result, not work");
        try completed(tasks, 0, 1);
        _ = tasks.shutdown();
    }
    try std.testing.expectEqual(counted.allocated_bytes, counted.freed_bytes);
}

test "lifecycle: handler error retires actor, joins and preserves sibling progress" {
    var control = Control{ .fail = true };
    const tasks = try Runtime.create(std.testing.allocator, io, .{ "a", "b" });
    defer tasks.deinit() catch unreachable;
    defer _ = tasks.shutdown();
    tasks.control = &control;
    _ = try tasks.trySend(1, "fail");
    try waitEntered(&control);
    for (0..4) |_| _ = try tasks.trySend(1, "discard");
    control.release.set(io);
    try completed(tasks, 0, 1);
    try std.testing.expectEqual(Runtime.Exit.handler_failed, try tasks.stopAndJoin(1));
    try std.testing.expect(tasks.whereis("a") == null);
    _ = try tasks.trySend(2, "still live");
    try completed(tasks, 1, 1);
    _ = tasks.shutdown();
    var failed: usize = 0;
    var stopped: usize = 0;
    var digests: usize = 0;
    while (try tasks.nextResult()) |result| switch (result.outcome) {
        .handler_failed => failed += 1,
        .stopped => stopped += 1,
        .digest => digests += 1,
        .canceled => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqual(@as(usize, 1), failed);
    try std.testing.expectEqual(@as(usize, 4), stopped);
    try std.testing.expectEqual(@as(usize, 1), digests);
}

test "lifecycle: canceled insertion rolls back copy; exhaustion never wraps IDs" {
    var counted = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const tasks = try Runtime.create(counted.allocator(), io, .{ "a", "b" });
    defer tasks.deinit() catch unreachable;
    defer _ = tasks.shutdown();
    const Sender = struct {
        tasks: *Runtime,
        started: std.Io.Event = .unset,
        fn run(self: *@This()) !u64 {
            self.started.set(io);
            return self.tasks.trySend(1, "abc");
        }
    };
    var sender = Sender{ .tasks = tasks };
    const result = canceled: {
        tasks.slots[0].mailbox.queue.type_erased.mutex.lockUncancelable(io);
        defer tasks.slots[0].mailbox.queue.type_erased.mutex.unlock(io);
        var task = try io.concurrent(Sender.run, .{&sender});
        defer _ = task.cancel(io) catch 0;
        try sender.started.wait(io);
        break :canceled task.cancel(io);
    };
    try std.testing.expectError(error.Canceled, result);
    try std.testing.expectEqual(@sizeOf(Runtime), counted.allocated_bytes - counted.freed_bytes);
    try std.testing.expectError(error.ActorNotFound, tasks.trySend(0, "abc"));
    counted.fail_index = counted.alloc_index;
    try std.testing.expectError(error.OutOfMemory, tasks.trySend(1, "abc"));
    counted.fail_index = std.math.maxInt(usize);
    tasks.next_id = std.math.maxInt(u64);
    try std.testing.expectEqual(std.math.maxInt(u64), try tasks.trySend(1, "abc"));
    try std.testing.expectError(error.RequestIdExhausted, tasks.trySend(2, "abc"));
    try std.testing.expectEqual(std.math.maxInt(u64), (try tasks.nextResult()).?.request_id);
}
