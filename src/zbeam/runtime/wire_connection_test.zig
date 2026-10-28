const std = @import("std");
const etf = @import("zbeam-etf");
const protocol = @import("zbeam-protocol");
const transport = @import("zbeam-transport");
const Runtime = @import("task_runtime.zig");
const connection = @import("wire_connection.zig");
const worker = @import("worker.zig");
const dist = protocol.distribution;
const testing = std.testing;
const io = testing.io;
const peer = transport.handshake_io.Peer{ .node_name = "peer@host", .creation = 2, .flags = worker.monitor_flags };
const from = etf.Pid{ .node = "peer@host", .creation = 2, .id = 4, .serial = 0 };
const pids = [2]etf.Pid{
    .{ .node = "native@host", .creation = 1, .id = 1, .serial = 0 },
    .{ .node = "native@host", .creation = 1, .id = 2, .serial = 0 },
};

fn reference(id: u32) etf.Reference {
    return .{ .node = peer.node_name, .creation = 2, .ids = .{ id, 0, 0, 0, 0 }, .len = 1 };
}

fn send(writer: *std.Io.Writer, to: etf.Pid, id: u32, payload: []const u8) !void {
    var control = [_]etf.Term{ .{ .integer = dist.send }, .{ .atom = "" }, .{ .pid = to } };
    var command = [_]etf.Term{ .{ .atom = "hash" }, .{ .binary = payload } };
    var body = [_]etf.Term{ .{ .pid = from }, .{ .reference = reference(id) }, .{ .tuple = &command } };
    const bytes = try dist.encodePacket(testing.allocator, &.{ .tuple = &control }, &.{ .tuple = &body });
    defer testing.allocator.free(bytes);
    try transport.distribution_io.writePacket(writer, bytes);
}

fn read(reader: *std.Io.Reader) !etf.Term {
    const bytes = try transport.deadline.run(io, testing.allocator, .fromSeconds(5), transport.distribution_io.readPacket, .{ testing.allocator, reader, worker.limits.max_packet_bytes }, drop);
    defer testing.allocator.free(bytes);
    var packet = try dist.decodePacket(testing.allocator, bytes, worker.limits);
    defer packet.deinit(testing.allocator);
    return packet.message.decodePayload(testing.allocator, worker.limits.etf);
}

fn drop(bytes: []u8, allocator: std.mem.Allocator) void {
    allocator.free(bytes);
}

fn expectDisconnect(result: anyerror!void) !void {
    if (result) |_| return error.TestUnexpectedResult else |err| {
        try testing.expect(err == error.EndOfStream or err == error.ConnectionResetByPeer or err == error.BrokenPipe or err == error.WriteFailed);
    }
}

fn pair() !struct { std.Io.net.Stream, std.Io.net.Stream } {
    const address: std.Io.net.IpAddress = .{ .ip4 = .loopback(0) };
    var server = try address.listen(io, .{ .reuse_address = true });
    defer server.deinit(io);
    const client = try server.socket.address.connect(io, .{ .mode = .stream });
    errdefer client.close(io);
    return .{ client, try server.accept(io) };
}

test "internal connection replies to both actors with exact correlation" {
    const tasks = try Runtime.create(testing.allocator, io, .{ "a", "b" });
    defer tasks.deinit() catch unreachable;
    defer _ = tasks.shutdown();
    const streams = try pair();
    var client_open = true;
    defer if (client_open) streams[0].close(io);
    defer streams[1].close(io);
    var server = try io.concurrent(connection.serve, .{ io, testing.allocator, streams[1], &peer, tasks, pids, 1, connection.Config{} });
    defer _ = server.cancel(io) catch {};
    var writer = streams[0].writer(io, &.{});
    var reader = streams[0].reader(io, &.{});
    try send(&writer.interface, pids[0], 11, "abc");
    try send(&writer.interface, pids[1], 12, "abc");
    var seen: [2]bool = @splat(false);
    for (0..2) |_| {
        var value = try read(&reader.interface);
        defer value.deinit(testing.allocator);
        const id = value.tuple[0].reference.ids[0];
        try testing.expect(id == 11 or id == 12);
        try testing.expect(!seen[id - 11]);
        seen[id - 11] = true;
        try testing.expectEqualStrings("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", &std.fmt.bytesToHex(value.tuple[1].tuple[1].binary[0..32].*, .lower));
    }
    streams[0].close(io);
    client_open = false;
    try expectDisconnect(server.await(io));
}

test "disconnect drains accepted old-epoch work before a new peer" {
    var control = @import("task_runtime_test.zig").Control{};
    const tasks = try Runtime.create(testing.allocator, io, .{ "a", "b" });
    defer tasks.deinit() catch unreachable;
    defer _ = tasks.shutdown();
    tasks.control = &control;
    const first = try pair();
    var first_open = true;
    defer if (first_open) first[0].close(io);
    defer first[1].close(io);
    var old = try io.concurrent(connection.serve, .{ io, testing.allocator, first[1], &peer, tasks, pids, 1, connection.Config{} });
    defer {
        control.release.set(io);
        _ = old.cancel(io) catch {};
    }
    var writer = first[0].writer(io, &.{});
    try send(&writer.interface, pids[0], 1, "old");
    try control.entered.waitTimeout(io, .{ .duration = .{ .raw = .fromSeconds(5), .clock = .awake } });
    first[0].close(io);
    first_open = false;
    control.release.set(io);
    try expectDisconnect(old.await(io));
    tasks.control = null;
    const second = try pair();
    var second_open = true;
    defer if (second_open) second[0].close(io);
    defer second[1].close(io);
    var fresh = try io.concurrent(connection.serve, .{ io, testing.allocator, second[1], &peer, tasks, pids, 2, connection.Config{} });
    defer _ = fresh.cancel(io) catch {};
    var next_writer = second[0].writer(io, &.{});
    var next_reader = second[0].reader(io, &.{});
    try send(&next_writer.interface, pids[1], 2, "abc");
    var value = try read(&next_reader.interface);
    defer value.deinit(testing.allocator);
    try testing.expectEqual(@as(u32, 2), value.tuple[0].reference.ids[0]);
    try testing.expectEqualStrings("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", &std.fmt.bytesToHex(value.tuple[1].tuple[1].binary[0..32].*, .lower));
    second[0].close(io);
    second_open = false;
    try expectDisconnect(fresh.await(io));
}

const FaultIo = struct {
    var calls: std.atomic.Value(usize) = .init(0);
    var reject: usize = 0;
    var block_write: bool = false;
    var fail_write: bool = false;
    var collector_started: std.Io.Event = .unset;
    var group_joined: std.Io.Event = .unset;
    var write_entered: std.Io.Event = .unset;

    fn reset() void {
        calls.store(0, .monotonic);
        reject = 0;
        block_write = false;
        fail_write = false;
        collector_started = .unset;
        group_joined = .unset;
        write_entered = .unset;
    }

    fn concurrent(userdata: ?*anyopaque, group: *std.Io.Group, context: []const u8, alignment: std.mem.Alignment, start: *const fn (*const anyopaque) void) std.Io.ConcurrentError!void {
        const n = calls.fetchAdd(1, .monotonic) + 1;
        if (n == reject) return error.ConcurrencyUnavailable;
        try io.vtable.groupConcurrent(userdata, group, context, alignment, start);
        if (n == 3) collector_started.set(io);
    }

    fn cancel(userdata: ?*anyopaque, group: *std.Io.Group, token: *anyopaque) void {
        io.vtable.groupCancel(userdata, group, token);
        group_joined.set(io);
    }

    fn operate(userdata: ?*anyopaque, operation: std.Io.Operation) std.Io.Cancelable!std.Io.Operation.Result {
        if (operation == .net_write) {
            write_entered.set(io);
            if (block_write) try io.sleep(.fromSeconds(60), .awake);
            if (fail_write) return .{ .net_write = error.ConnectionResetByPeer };
        }
        return io.vtable.operate(userdata, operation);
    }

    fn vtable() std.Io.VTable {
        var result = io.vtable.*;
        result.groupConcurrent = concurrent;
        result.groupCancel = cancel;
        result.operate = operate;
        return result;
    }
};

fn expectDrained(tasks: *Runtime) !void {
    tasks.mutex.lockUncancelable(io);
    defer tasks.mutex.unlock(io);
    try testing.expect(!tasks.wire_reservation_active);
    for (tasks.slots) |slot| for (slot.ledger.records) |record| {
        try testing.expect(record.stage == .free);
    };
}

test "connection rejects reader and collector launches without stranded work" {
    for (1..4) |reject| {
        FaultIo.reset();
        FaultIo.reject = reject;
        var vtable = FaultIo.vtable();
        const context = std.Io{ .userdata = io.userdata, .vtable = &vtable };
        const tasks = try Runtime.create(testing.allocator, io, .{ "a", "b" });
        defer tasks.deinit() catch unreachable;
        defer _ = tasks.shutdown();
        const streams = try pair();
        defer streams[0].close(io);
        defer streams[1].close(io);
        var writer = streams[0].writer(io, &.{});
        try send(&writer.interface, pids[0], 1, "abc");
        try testing.expectError(error.ConcurrencyUnavailable, connection.serve(context, testing.allocator, streams[1], &peer, tasks, pids, 1, .{ .frame_timeout = null, .write_timeout = null }));
        try testing.expectEqual(reject, FaultIo.calls.load(.monotonic));
        try expectDrained(tasks);
    }
}

test "partial frame deadlines and decoder failure release all reservations" {
    const cases = [_][]const u8{ &.{}, &.{ 0, 0 }, &.{ 0, 0, 0, 2, 112 }, &.{ 0, 0, 0, 1, 0 } };
    for (cases, 0..) |bytes, index| {
        const tasks = try Runtime.create(testing.allocator, io, .{ "a", "b" });
        defer tasks.deinit() catch unreachable;
        defer _ = tasks.shutdown();
        const streams = try pair();
        defer streams[0].close(io);
        defer streams[1].close(io);
        var writer = streams[0].writer(io, &.{});
        try writer.interface.writeAll(bytes);
        const result = connection.serve(io, testing.allocator, streams[1], &peer, tasks, pids, 1, .{ .frame_timeout = .fromMilliseconds(10) });
        if (index < 3) {
            try testing.expectError(error.Timeout, result);
        } else if (result) |_| return error.TestUnexpectedResult else |err| {
            try testing.expect(err != error.Timeout);
        }
        try expectDrained(tasks);
    }
}

test "failed and blocked writers drop collected results and join their reader" {
    for ([_]bool{ false, true }) |blocked| {
        FaultIo.reset();
        FaultIo.block_write = blocked;
        FaultIo.fail_write = !blocked;
        var vtable = FaultIo.vtable();
        const context = std.Io{ .userdata = io.userdata, .vtable = &vtable };
        const tasks = try Runtime.create(testing.allocator, io, .{ "a", "b" });
        defer tasks.deinit() catch unreachable;
        defer _ = tasks.shutdown();
        const streams = try pair();
        defer streams[0].close(io);
        defer streams[1].close(io);
        var writer = streams[0].writer(io, &.{});
        try send(&writer.interface, pids[0], 1, "abc");
        const result = connection.serve(context, testing.allocator, streams[1], &peer, tasks, pids, 1, .{ .frame_timeout = null, .write_timeout = .fromMilliseconds(20) });
        try testing.expectError(if (blocked) error.Timeout else error.WriteFailed, result);
        try testing.expect(FaultIo.write_entered.isSet());
        try expectDrained(tasks);
    }
}

test "cancellation joins read and collector before waiting for accepted work" {
    FaultIo.reset();
    var vtable = FaultIo.vtable();
    const context = std.Io{ .userdata = io.userdata, .vtable = &vtable };
    var control = @import("task_runtime_test.zig").Control{};
    const tasks = try Runtime.create(testing.allocator, io, .{ "a", "b" });
    defer tasks.deinit() catch unreachable;
    defer _ = tasks.shutdown();
    tasks.control = &control;
    const streams = try pair();
    defer streams[0].close(io);
    defer streams[1].close(io);
    var server = try io.concurrent(connection.serve, .{ context, testing.allocator, streams[1], &peer, tasks, pids, 1, connection.Config{ .frame_timeout = null, .write_timeout = null } });
    defer {
        control.release.set(io);
        _ = server.cancel(io) catch {};
    }
    var writer = streams[0].writer(io, &.{});
    try send(&writer.interface, pids[0], 1, "held");
    const timeout: std.Io.Timeout = .{ .duration = .{ .raw = .fromSeconds(5), .clock = .awake } };
    try control.entered.waitTimeout(io, timeout);
    try FaultIo.collector_started.waitTimeout(io, timeout);
    const Cancel = struct {
        fn run(future: *@TypeOf(server), done: *std.Io.Event) anyerror!void {
            defer done.set(io);
            return future.cancel(io);
        }
    };
    var done: std.Io.Event = .unset;
    var cancel = try io.concurrent(Cancel.run, .{ &server, &done });
    defer {
        control.release.set(io);
        _ = cancel.await(io) catch {};
    }
    try FaultIo.group_joined.waitTimeout(io, timeout);
    try testing.expect(!done.isSet());
    control.release.set(io);
    try testing.expectError(error.Canceled, cancel.await(io));
    try expectDrained(tasks);
}

test "disconnect joins old connection operations before waiting for accepted work" {
    FaultIo.reset();
    var vtable = FaultIo.vtable();
    const context = std.Io{ .userdata = io.userdata, .vtable = &vtable };
    var control = @import("task_runtime_test.zig").Control{};
    const tasks = try Runtime.create(testing.allocator, io, .{ "a", "b" });
    defer tasks.deinit() catch unreachable;
    defer _ = tasks.shutdown();
    tasks.control = &control;
    const streams = try pair();
    var client_open = true;
    defer if (client_open) streams[0].close(io);
    defer streams[1].close(io);
    const Runner = struct {
        fn serve(ctx: std.Io, stream: std.Io.net.Stream, runtime: *Runtime, done: *std.Io.Event) anyerror!void {
            defer done.set(io);
            return connection.serve(ctx, testing.allocator, stream, &peer, runtime, pids, 1, .{ .frame_timeout = null, .write_timeout = null });
        }
    };
    var done: std.Io.Event = .unset;
    var old = try io.concurrent(Runner.serve, .{ context, streams[1], tasks, &done });
    defer {
        control.release.set(io);
        _ = old.cancel(io) catch {};
    }
    var writer = streams[0].writer(io, &.{});
    try send(&writer.interface, pids[0], 1, "old");
    const timeout: std.Io.Timeout = .{ .duration = .{ .raw = .fromSeconds(5), .clock = .awake } };
    try control.entered.waitTimeout(io, timeout);
    try FaultIo.collector_started.waitTimeout(io, timeout);
    streams[0].close(io);
    client_open = false;
    try FaultIo.group_joined.waitTimeout(io, timeout);
    try testing.expect(!done.isSet());
    control.release.set(io);
    try expectDisconnect(old.await(io));
    try testing.expect(done.isSet());
    try expectDrained(tasks);
}
