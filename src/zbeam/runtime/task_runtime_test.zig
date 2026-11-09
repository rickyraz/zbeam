//! Imported only by test builds; no fault switch or pause hook exists in production.
const std = @import("std");
const Runtime = @import("task_runtime.zig");
const admission = @import("task_admission.zig");
const io = std.testing.io;

const Phase = enum { before_claim, active };
pub const Control = struct {
    actor: usize = 0,
    phase: Phase = .active,
    entered: std.Io.Event = .unset,
    release: std.Io.Event = .unset,
    active_entries: std.atomic.Value(usize) = .init(0),
    fail: bool = false,
    spin: bool = false,

    pub fn checkpoint(self: *@This(), context: std.Io, actor: usize, phase: Phase) !void {
        if (actor != self.actor) return;
        if (phase == .active) _ = self.active_entries.fetchAdd(1, .monotonic);
        if (phase != self.phase) return;
        self.entered.set(context);
        if (self.spin) while (true) std.atomic.spinLoopHint();
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

test "lifecycle: compiled handler returns bounded bytes on both actors" {
    const Handler = struct {
        fn apply(input: []const u8, output: []u8) error{HandlerFailed}!usize {
            for (input, 0..) |byte, i| output[i] = std.ascii.toUpper(byte);
            return input.len;
        }
    };
    const tasks = try Runtime.createWithHandler(std.testing.allocator, io, .{ "a", "b" }, Handler.apply);
    defer tasks.deinit() catch unreachable;
    defer _ = tasks.shutdown();

    const input = try std.testing.allocator.alloc(u8, Runtime.max_output);
    defer std.testing.allocator.free(input);
    @memset(input, 'a');
    for ([_]usize{ 0, 32, 33, Runtime.max_output }, 0..) |len, i| {
        const id = try tasks.trySend(i % 2 + 1, input[0..len]);
        const result = (try tasks.nextResult()).?;
        try std.testing.expectEqual(id, result.request_id);
        try std.testing.expect(result.outcome == .digest);
        try std.testing.expectEqual(@as([32]u8, @splat(0)), result.outcome.digest);
        try std.testing.expectEqual(len, result.output.len);
        for (result.output) |byte| try std.testing.expectEqual(@as(u8, 'A'), byte);
    }
}

test "lifecycle: compiled handler failures retire only the affected actor" {
    const Handler = struct {
        fn apply(input: []const u8, output: []u8) error{HandlerFailed}!usize {
            if (std.mem.eql(u8, input, "error")) return error.HandlerFailed;
            if (std.mem.eql(u8, input, "too long")) return output.len + 1;
            output[0] = 42;
            return 1;
        }
    };
    for ([_][]const u8{ "error", "too long" }) |input| {
        const tasks = try Runtime.createWithHandler(std.testing.allocator, io, .{ "a", "b" }, Handler.apply);
        defer tasks.deinit() catch unreachable;
        defer _ = tasks.shutdown();
        _ = try tasks.trySend(1, input);
        const failed = (try tasks.nextResult()).?;
        try std.testing.expect(failed.outcome == .handler_failed);
        try std.testing.expectEqual(@as(usize, 0), failed.output.len);
        try std.testing.expectEqual(Runtime.Exit.handler_failed, try tasks.stopAndJoin(1));
        try std.testing.expectError(error.ActorStopped, tasks.trySend(1, "late"));
        _ = try tasks.trySend(2, "ok");
        const sibling = (try tasks.nextResult()).?;
        try std.testing.expectEqualSlices(u8, &.{42}, sibling.output);
    }
}

test "lifecycle: handler buffers are zeroed and collected output survives ticket reuse" {
    const Handler = struct {
        fn apply(input: []const u8, output: []u8) error{HandlerFailed}!usize {
            // Stale bytes from an earlier request on this ticket would fail here.
            for (output) |byte| if (byte != 0) return error.HandlerFailed;
            @memset(output[0..1000], input[0]);
            return if (input.len == 1) 1000 else 1;
        }
    };
    const tasks = try Runtime.createWithHandler(std.testing.allocator, io, .{ "a", "b" }, Handler.apply);
    defer tasks.deinit() catch unreachable;
    defer _ = tasks.shutdown();
    _ = try tasks.trySend(1, "x");
    const first = (try tasks.nextResult()).?;
    try std.testing.expectEqual(@as(usize, 1000), first.output.len);
    // Reuse actor a's tickets, including the first one's, while `first` is borrowed.
    for (0..admission.queue_capacity) |_| _ = try tasks.trySend(1, "yy");
    while (true) {
        tasks.mutex.lockUncancelable(io);
        var complete: usize = 0;
        for (tasks.slots[0].ledger.records) |record| complete += @intFromBool(record.stage == .complete);
        tasks.mutex.unlock(io);
        if (complete == admission.queue_capacity) break;
        try io.sleep(.fromMilliseconds(1), .awake);
    }
    for (first.output) |byte| try std.testing.expectEqual(@as(u8, 'x'), byte);
    for (0..admission.queue_capacity) |_| {
        const later = (try tasks.nextResult()).?;
        try std.testing.expect(later.outcome == .digest);
        try std.testing.expectEqualSlices(u8, "y", later.output);
    }
}

test "lifecycle: SHA-256 runtimes allocate no handler output storage" {
    var counted = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const tasks = try Runtime.create(counted.allocator(), io, .{ "a", "b" });
    defer tasks.deinit() catch unreachable;
    defer _ = tasks.shutdown();
    try std.testing.expectEqual(@sizeOf(Runtime), counted.allocated_bytes - counted.freed_bytes);
    try std.testing.expect(tasks.outputs == null);
}

test "lifecycle: noncooperative spin requires external process termination" {
    const enabled = std.testing.environ.getAlloc(std.testing.allocator, "ZBEAM_M2_SPIN_PROBE") catch |err| switch (err) {
        error.EnvironmentVariableMissing => return error.SkipZigTest,
        else => return err,
    };
    defer std.testing.allocator.free(enabled);
    if (!std.mem.eql(u8, enabled, "1")) return error.SkipZigTest;
    const Shim = struct {
        fn cancel(userdata: ?*anyopaque, future: *std.Io.AnyFuture, result: []u8, alignment: std.mem.Alignment) void {
            std.debug.print("M2_JOIN_WAIT\n", .{});
            std.testing.io.vtable.cancel(userdata, future, result, alignment);
        }
    };
    var vtable = io.vtable.*;
    vtable.cancel = Shim.cancel;
    const wrapped = std.Io{ .userdata = io.userdata, .vtable = &vtable };
    var control = Control{ .spin = true };
    const tasks = try Runtime.create(std.testing.allocator, wrapped, .{ "a", "b" });
    defer tasks.deinit() catch unreachable;
    defer _ = tasks.shutdown();
    tasks.control = &control;
    _ = try tasks.trySend(1, "noncooperative");
    try waitEntered(&control);
    std.debug.print("M2_SPIN_ENTERED\n", .{});
    _ = tasks.shutdown();
    return error.TestUnexpectedResult;
}

test "lifecycle: noncooperative compiled handler requires external process termination" {
    const enabled = std.testing.environ.getAlloc(std.testing.allocator, "ZBEAM_M2_SPIN_PROBE") catch |err| switch (err) {
        error.EnvironmentVariableMissing => return error.SkipZigTest,
        else => return err,
    };
    defer std.testing.allocator.free(enabled);
    if (!std.mem.eql(u8, enabled, "handler")) return error.SkipZigTest;
    const Handler = struct {
        var entered: std.atomic.Value(bool) = .init(false);
        fn apply(_: []const u8, _: []u8) error{HandlerFailed}!usize {
            std.debug.print("M2_SPIN_ENTERED\n", .{});
            entered.store(true, .release);
            while (true) std.atomic.spinLoopHint();
        }
        fn cancel(userdata: ?*anyopaque, future: *std.Io.AnyFuture, result: []u8, alignment: std.mem.Alignment) void {
            std.debug.print("M2_JOIN_WAIT\n", .{});
            std.testing.io.vtable.cancel(userdata, future, result, alignment);
        }
    };
    var vtable = io.vtable.*;
    vtable.cancel = Handler.cancel;
    const wrapped = std.Io{ .userdata = io.userdata, .vtable = &vtable };
    const tasks = try Runtime.createWithHandler(std.testing.allocator, wrapped, .{ "a", "b" }, Handler.apply);
    defer tasks.deinit() catch unreachable;
    defer _ = tasks.shutdown();
    _ = try tasks.trySend(1, "noncooperative handler");
    while (!Handler.entered.load(.acquire)) std.atomic.spinLoopHint();
    _ = tasks.shutdown();
    return error.TestUnexpectedResult;
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
