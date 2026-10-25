const std = @import("std");
const etf = @import("zbeam-etf");
const protocol = @import("zbeam-protocol");
const dist = protocol.distribution;
const framing = @import("zbeam-transport").distribution_io;
const Worker = @import("worker.zig").Worker;
const f = @import("worker_test.zig");
const peer = @import("zbeam-transport").handshake_io.Peer{ .node_name = f.sender.node, .creation = f.sender.creation, .flags = @import("worker.zig").monitor_flags };

fn ref(id: u32) etf.Reference {
    var result = f.reference;
    result.ids[0] = id;
    return result;
}

fn signal(allocator: std.mem.Allocator, state: *Worker, op: i64, target: etf.Pid, reference: etf.Reference, writer: *std.Io.Writer) !void {
    var fields = [_]etf.Term{ .{ .integer = op }, .{ .pid = f.sender }, .{ .pid = target }, .{ .reference = reference } };
    const bytes = try dist.encodePacket(allocator, &.{ .tuple = &fields }, null);
    defer allocator.free(bytes);
    try state.handle(allocator, bytes, &peer, writer);
}

fn count(state: *const Worker) usize {
    var n: usize = 0;
    for (state.subscriptions) |slot| if (slot != null) {
        n += 1;
    };
    return n;
}

test "monitors are idempotent, demonitorable and retain no decoded frame slices" {
    var state = Worker{ .pid = f.native };
    try state.start();
    var storage: [4096]u8 = undefined;
    var output = std.Io.Writer.fixed(&storage);
    try signal(std.testing.allocator, &state, 19, f.native, ref(1), &output);
    try signal(std.testing.allocator, &state, 19, f.native, ref(1), &output);
    try std.testing.expectEqual(@as(usize, 1), count(&state));
    try std.testing.expect(state.subscriptions[0].?.reference.node.ptr == peer.node_name.ptr);
    try std.testing.expect(state.subscriptions[0].?.watcher.node.ptr == peer.node_name.ptr);
    try signal(std.testing.allocator, &state, 20, f.native, ref(1), &output);
    try signal(std.testing.allocator, &state, 20, f.native, ref(1), &output);
    try std.testing.expectEqual(@as(usize, 0), count(&state));
    try std.testing.expectEqual(@as(usize, 0), output.end);
    var stale = f.native;
    stale.id += 1;
    try signal(std.testing.allocator, &state, 19, stale, ref(2), &output);
    var result = try dist.decodePacket(std.testing.allocator, output.buffered(), .{});
    defer result.deinit(std.testing.allocator);
    const parsed = try protocol.monitor.parse(&result.message.control);
    try std.testing.expectEqual(protocol.monitor.Kind.exited, parsed.kind);
    try std.testing.expectEqualStrings("noproc", parsed.reason.?.atom);
    try std.testing.expect(parsed.target.pid.eql(stale) and parsed.reference.eql(ref(2)));
}

fn stopMonitored(allocator: std.mem.Allocator) !void {
    var state = Worker{ .pid = f.native };
    try state.start();
    defer std.debug.assert(state.state != .stopping);
    var storage: [8192]u8 = undefined;
    var output = std.Io.Writer.fixed(&storage);
    for (1..4) |i| try signal(allocator, &state, 19, f.native, ref(@intCast(i)), &output);
    try signal(allocator, &state, 20, f.native, ref(2), &output);
    const bytes = try f.request(allocator, f.native, .{ .atom = "stop" });
    defer allocator.free(bytes);
    state.handle(allocator, bytes, &peer, &output) catch |err| {
        if (state.state == .stopped) try std.testing.expectEqual(@as(usize, 0), count(&state));
        return err;
    };
    try std.testing.expectEqual(@import("worker.zig").State.stopped, state.state);
    try std.testing.expectEqual(@as(usize, 0), count(&state));
    var reader = std.Io.Reader.fixed(output.buffered());
    var seen = [_]bool{ false, false, false, false };
    for (0..3) |index| {
        const packet = try framing.readPacket(allocator, &reader, 8192);
        defer allocator.free(packet);
        var decoded = try dist.decodePacket(allocator, packet, .{});
        defer decoded.deinit(allocator);
        if (index == 0) continue; // The correlated stop acknowledgement precedes DOWNs.
        const parsed = try protocol.monitor.parse(&decoded.message.control);
        const id = parsed.reference.ids[0];
        try std.testing.expect(id == 1 or id == 3);
        try std.testing.expect(!seen[id]);
        seen[id] = true;
        try std.testing.expect(parsed.target.pid.eql(f.native) and parsed.watcher.eql(f.sender));
        try std.testing.expectEqualStrings("normal", parsed.reason.?.atom);
    }
    try std.testing.expectEqual(reader.buffer.len, reader.seek);
}

test "normal stop emits each surviving monitor once and cleans up on allocation errors" {
    try stopMonitored(std.testing.allocator);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, stopMonitored, .{});
}

test "monitor exhaustion is explicit and connection cleanup releases the fixed table" {
    var state = Worker{ .pid = f.native };
    try state.start();
    var output = std.Io.Writer.fixed(&.{});
    for (0..64) |i| try signal(std.testing.allocator, &state, 19, f.native, ref(@intCast(i)), &output);
    try std.testing.expectError(error.MonitorLimit, signal(std.testing.allocator, &state, 19, f.native, ref(64), &output));
    try std.testing.expectEqual(@as(usize, 64), count(&state));
    state.clearMonitors();
    try std.testing.expectEqual(@as(usize, 0), count(&state));
}

test "reference reuse cannot change target and foreign references cannot subscribe" {
    var state = Worker{ .pid = f.native };
    try state.start();
    var output = std.Io.Writer.fixed(&.{});
    var foreign = ref(1);
    foreign.creation += 1;
    try std.testing.expectError(error.UnexpectedPeer, signal(std.testing.allocator, &state, 19, f.native, foreign, &output));
    try signal(std.testing.allocator, &state, 19, f.native, ref(1), &output);
    var old = f.native;
    old.serial += 1;
    try std.testing.expectError(error.InvalidControl, signal(std.testing.allocator, &state, 19, old, ref(1), &output));
    try std.testing.expectEqual(@as(usize, 1), count(&state));
}

test "named discovery subscription outlives normal worker stop" {
    var state = Worker{ .pid = f.native };
    try state.start();
    var fields = [_]etf.Term{ .{ .integer = 19 }, .{ .pid = f.sender }, .{ .atom = "zbeam_worker" }, .{ .reference = ref(1) } };
    const bytes = try dist.encodePacket(std.testing.allocator, &.{ .tuple = &fields }, null);
    defer std.testing.allocator.free(bytes);
    var storage: [4096]u8 = undefined;
    var output = std.Io.Writer.fixed(&storage);
    try std.testing.expectError(error.UnnegotiatedMonitor, state.handle(std.testing.allocator, bytes, &f.peer, &output));
    try state.handle(std.testing.allocator, bytes, &peer, &output);
    const stop = try f.request(std.testing.allocator, f.native, .{ .atom = "stop" });
    defer std.testing.allocator.free(stop);
    try state.handle(std.testing.allocator, stop, &peer, &output);
    try std.testing.expectEqual(@as(usize, 1), count(&state));
    try std.testing.expectEqualStrings("zbeam_worker", state.subscriptions[0].?.target.name);
    var decoded = try dist.decodePacket(std.testing.allocator, output.buffered(), .{});
    defer decoded.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i64, dist.send), decoded.message.control.tuple[0].integer);
    fields[0] = .{ .integer = 20 };
    const demonitor = try dist.encodePacket(std.testing.allocator, &.{ .tuple = &fields }, null);
    defer std.testing.allocator.free(demonitor);
    try state.handle(std.testing.allocator, demonitor, &peer, &output);
    try std.testing.expectEqual(@as(usize, 0), count(&state));
}

test "stop write failure still retires the identity and subscriptions" {
    var state = Worker{ .pid = f.native };
    try state.start();
    var output = std.Io.Writer.fixed(&.{});
    try signal(std.testing.allocator, &state, 19, f.native, ref(1), &output);
    const bytes = try f.request(std.testing.allocator, f.native, .{ .atom = "stop" });
    defer std.testing.allocator.free(bytes);
    try std.testing.expectError(error.WriteFailed, state.handle(std.testing.allocator, bytes, &peer, &output));
    try std.testing.expectEqual(@import("worker.zig").State.stopped, state.state);
    try std.testing.expectEqual(@as(usize, 0), count(&state));
}
