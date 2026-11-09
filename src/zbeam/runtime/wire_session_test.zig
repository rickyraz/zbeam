const std = @import("std");
const etf = @import("zbeam-etf");
const protocol = @import("zbeam-protocol");
const transport = @import("zbeam-transport");
const Runtime = @import("task_runtime.zig");
const Session = @import("wire_session.zig").Session;
const gate = @import("wire_gate.zig");
const worker = @import("worker.zig");
const dist = protocol.distribution;
const testing = std.testing;
const io = testing.io;
const peer = transport.handshake_io.Peer{ .node_name = "peer@host", .creation = 2, .flags = worker.monitor_flags };
const from = etf.Pid{ .node = "peer@host", .creation = 2, .id = 4, .serial = 0 };
const reference = etf.Reference{ .node = "peer@host", .creation = 2, .ids = .{ 1, 2, 0, 0, 0 }, .len = 2 };
const pids = [2]etf.Pid{
    .{ .node = "native@host", .creation = 1, .id = 1, .serial = 0 },
    .{ .node = "native@host", .creation = 1, .id = 2, .serial = 0 },
};
const Reader = struct {
    interface: std.Io.Reader = .{ .vtable = &.{ .stream = stream }, .buffer = &.{}, .seek = 0, .end = 0 },
    bytes: []const u8,
    fn stream(interface: *std.Io.Reader, writer: *std.Io.Writer, limit: std.Io.Limit) std.Io.Reader.StreamError!usize {
        const self: *Reader = @fieldParentPtr("interface", interface);
        if (self.bytes.len == 0) return error.EndOfStream;
        const n = try writer.write(self.bytes[0..limit.minInt(self.bytes.len)]);
        self.bytes = self.bytes[n..];
        return n;
    }
};

fn deliver(session: *Session, control: *const etf.Term, payload: ?*const etf.Term, writer: *std.Io.Writer) !void {
    const source = try dist.encodePacket(testing.allocator, control, payload);
    defer testing.allocator.free(source);
    var reader = Reader{ .bytes = source };
    var frame = try gate.begin(session.tasks, &session.outputs);
    defer if (frame.active) frame.release();
    const bytes = try frame.read(testing.allocator, &reader.interface, worker.limits.max_packet_bytes);
    defer testing.allocator.free(bytes);
    try session.process(&frame, testing.allocator, bytes, writer);
}

fn request(session: *Session, target: etf.Pid, command: etf.Term, writer: *std.Io.Writer) !void {
    var control = [_]etf.Term{ .{ .integer = dist.send }, .{ .atom = "" }, .{ .pid = target } };
    var body = [_]etf.Term{ .{ .pid = from }, .{ .reference = reference }, command };
    try deliver(session, &.{ .tuple = &control }, &.{ .tuple = &body }, writer);
}

fn discovery(session: *Session, name: []const u8, writer: *std.Io.Writer) !void {
    var control = [_]etf.Term{ .{ .integer = dist.reg_send }, .{ .pid = from }, .{ .atom = "" }, .{ .atom = "zbeam_workers" } };
    var command = [_]etf.Term{ .{ .atom = "discover" }, .{ .atom = name } };
    var body = [_]etf.Term{ .{ .pid = from }, .{ .reference = reference }, .{ .tuple = &command } };
    try deliver(session, &.{ .tuple = &control }, &.{ .tuple = &body }, writer);
}

fn decodeReply(bytes: []const u8) !etf.Term {
    var packet = try dist.decodePacket(testing.allocator, bytes, worker.limits);
    defer packet.deinit(testing.allocator);
    return packet.message.decodePayload(testing.allocator, worker.limits.etf);
}

test "internal session discovers, hashes, stops one actor and preserves sibling" {
    const tasks = try Runtime.create(testing.allocator, io, .{ "a", "b" });
    defer tasks.deinit() catch unreachable;
    defer _ = tasks.shutdown();
    var session = Session.init(tasks, &peer, pids, 5);
    var buffer: [8192]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try discovery(&session, "a", &writer);
    var found = try decodeReply(writer.buffered());
    defer found.deinit(testing.allocator);
    try testing.expect(found.tuple[0].reference.eql(reference));
    try testing.expect(found.tuple[1].tuple[1].pid.eql(pids[0]));
    writer = .fixed(&buffer);
    var hash = [_]etf.Term{ .{ .atom = "hash" }, .{ .binary = "abc" } };
    try request(&session, pids[0], .{ .tuple = &hash }, &writer);
    try testing.expectEqual(@as(usize, 0), writer.buffered().len);
    const result = (try tasks.nextResult()).?;
    try session.result(result, &writer);
    var digest = try decodeReply(writer.buffered());
    defer digest.deinit(testing.allocator);
    try testing.expectEqualStrings("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", &std.fmt.bytesToHex(digest.tuple[1].tuple[1].binary[0..32].*, .lower));
    writer = .fixed(&buffer);
    var control = [_]etf.Term{ .{ .integer = protocol.monitor.monitor_p }, .{ .pid = from }, .{ .pid = pids[0] }, .{ .reference = reference } };
    try deliver(&session, &.{ .tuple = &control }, null, &writer);
    try request(&session, pids[0], .{ .atom = "stop" }, &writer);
    const frames = writer.buffered();
    const first_len = (@as(usize, frames[0]) << 24) | (@as(usize, frames[1]) << 16) | (@as(usize, frames[2]) << 8) | frames[3];
    var stopped = try decodeReply(frames[0 .. first_len + 4]);
    defer stopped.deinit(testing.allocator);
    try testing.expectEqualStrings("ok", stopped.tuple[1].atom);
    var exit_packet = try dist.decodePacket(testing.allocator, frames[first_len + 4 ..], worker.limits);
    defer exit_packet.deinit(testing.allocator);
    const exit = try protocol.monitor.parse(&exit_packet.message.control);
    try testing.expect(exit.target.pid.eql(pids[0]) and exit.reference.eql(reference));
    try testing.expectEqualStrings("normal", exit.reason.?.atom);
    writer = .fixed(&buffer);
    try request(&session, pids[1], .{ .tuple = &hash }, &writer);
    try session.result((try tasks.nextResult()).?, &writer);
    var sibling = try decodeReply(writer.buffered());
    defer sibling.deinit(testing.allocator);
    try testing.expectEqualStrings("ok", sibling.tuple[1].tuple[0].atom);
    writer = .fixed(&buffer);
    try discovery(&session, "a", &writer);
    var dead = try decodeReply(writer.buffered());
    defer dead.deinit(testing.allocator);
    try testing.expectEqualStrings("noproc", dead.tuple[1].tuple[1].atom);
    writer = .fixed(&buffer);
    try request(&session, pids[0], .{ .tuple = &hash }, &writer);
    try testing.expectEqual(@as(usize, 0), writer.buffered().len);
    session.monitors.clear();
    session.outputs.discard();
}

test "custom session separates commands and writes the exact bounded output" {
    const Handler = struct {
        fn apply(input: []const u8, output: []u8) error{HandlerFailed}!usize {
            if (input.len > output.len) return error.HandlerFailed;
            for (input, 0..) |byte, i| output[i] = std.ascii.toUpper(byte);
            return input.len;
        }
    };
    const tasks = try Runtime.createWithHandler(testing.allocator, io, .{ "a", "b" }, Handler.apply);
    defer tasks.deinit() catch unreachable;
    defer _ = tasks.shutdown();
    var session = Session.init(tasks, &peer, pids, 1);
    const buffer = try testing.allocator.alloc(u8, Runtime.max_output + 8192);
    defer testing.allocator.free(buffer);
    var writer = std.Io.Writer.fixed(buffer);
    var command = [_]etf.Term{ .{ .atom = "hash" }, .{ .binary = "abc" } };
    try request(&session, pids[0], .{ .tuple = &command }, &writer);
    var rejected = try decodeReply(writer.buffered());
    defer rejected.deinit(testing.allocator);
    try testing.expectEqualStrings("bad_request", rejected.tuple[1].tuple[1].atom);

    const input = try testing.allocator.alloc(u8, Runtime.max_output);
    defer testing.allocator.free(input);
    @memset(input, 'a');
    const expected = try testing.allocator.alloc(u8, Runtime.max_output);
    defer testing.allocator.free(expected);
    @memset(expected, 'A');
    command[0] = .{ .atom = "call" };
    for ([_]usize{ 0, 3, 32, 33, Runtime.max_output }, 0..) |len, i| {
        writer = .fixed(buffer);
        command[1] = .{ .binary = input[0..len] };
        try request(&session, pids[i % 2], .{ .tuple = &command }, &writer);
        try testing.expectEqual(@as(usize, 0), writer.buffered().len);
        try session.result((try tasks.nextResult()).?, &writer);
        var reply = try decodeReply(writer.buffered());
        defer reply.deinit(testing.allocator);
        try testing.expectEqualStrings(expected[0..len], reply.tuple[1].tuple[1].binary);
    }
    session.outputs.discard();
}

test "custom handler failure retires its actor without disabling the sibling" {
    const Handler = struct {
        fn apply(input: []const u8, output: []u8) error{HandlerFailed}!usize {
            if (std.mem.eql(u8, input, "fail")) return error.HandlerFailed;
            output[0] = 42;
            return 1;
        }
    };
    const tasks = try Runtime.createWithHandler(testing.allocator, io, .{ "a", "b" }, Handler.apply);
    defer tasks.deinit() catch unreachable;
    defer _ = tasks.shutdown();
    var session = Session.init(tasks, &peer, pids, 1);
    var buffer: [8192]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    var command = [_]etf.Term{ .{ .atom = "call" }, .{ .binary = "fail" } };
    try request(&session, pids[0], .{ .tuple = &command }, &writer);
    try session.result((try tasks.nextResult()).?, &writer);
    var failed = try decodeReply(writer.buffered());
    defer failed.deinit(testing.allocator);
    try testing.expectEqualStrings("handler_failed", failed.tuple[1].tuple[1].atom);
    try testing.expect(tasks.whereis("a") == null and tasks.whereis("b") != null);
    writer = .fixed(&buffer);
    command[1] = .{ .binary = "fresh" };
    try request(&session, pids[1], .{ .tuple = &command }, &writer);
    try session.result((try tasks.nextResult()).?, &writer);
    var sibling = try decodeReply(writer.buffered());
    defer sibling.deinit(testing.allocator);
    try testing.expectEqualSlices(u8, &.{42}, sibling.tuple[1].tuple[1].binary);
    session.outputs.discard();
}

test "invalid result length fails closed and releases its output credit" {
    const tasks = try Runtime.create(testing.allocator, io, .{ "a", "b" });
    defer tasks.deinit() catch unreachable;
    defer _ = tasks.shutdown();
    var session = Session.init(tasks, &peer, pids, 1);
    var buffer: [8192]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    var command = [_]etf.Term{ .{ .atom = "hash" }, .{ .binary = "abc" } };
    try request(&session, pids[0], .{ .tuple = &command }, &writer);
    var result = (try tasks.nextResult()).?;
    const oversized = try testing.allocator.alloc(u8, Runtime.max_output + 1);
    defer testing.allocator.free(oversized);
    result.output = oversized;
    try testing.expectError(error.InvalidOutputLength, session.result(result, &writer));
    try testing.expectError(error.UnknownCompletion, session.result(result, &writer));
    for (0..10) |_| _ = try session.outputs.reserve();
    try testing.expectError(error.WouldBlock, session.outputs.reserve());
    session.outputs.discard();
}

test "handler failure joins the actor and notifies its monitor once" {
    var control = @import("task_runtime_test.zig").Control{ .fail = true };
    const tasks = try Runtime.create(testing.allocator, io, .{ "a", "b" });
    defer tasks.deinit() catch unreachable;
    defer _ = tasks.shutdown();
    tasks.control = &control;
    var session = Session.init(tasks, &peer, pids, 1);
    var buffer: [8192]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    var monitor_fields = [_]etf.Term{ .{ .integer = protocol.monitor.monitor_p }, .{ .pid = from }, .{ .pid = pids[0] }, .{ .reference = reference } };
    try deliver(&session, &.{ .tuple = &monitor_fields }, null, &writer);
    var hash = [_]etf.Term{ .{ .atom = "hash" }, .{ .binary = "abc" } };
    try request(&session, pids[0], .{ .tuple = &hash }, &writer);
    try control.entered.waitTimeout(io, .{ .duration = .{ .raw = .fromSeconds(5), .clock = .awake } });
    control.release.set(io);
    try session.result((try tasks.nextResult()).?, &writer);
    const frames = writer.buffered();
    const first_len = (@as(usize, frames[0]) << 24) | (@as(usize, frames[1]) << 16) | (@as(usize, frames[2]) << 8) | frames[3];
    var failure = try decodeReply(frames[0 .. first_len + 4]);
    defer failure.deinit(testing.allocator);
    try testing.expectEqualStrings("handler_failed", failure.tuple[1].tuple[1].atom);
    var exit_packet = try dist.decodePacket(testing.allocator, frames[first_len + 4 ..], worker.limits);
    defer exit_packet.deinit(testing.allocator);
    const exit = try protocol.monitor.parse(&exit_packet.message.control);
    try testing.expectEqualStrings("handler_failed", exit.reason.?.atom);
    try testing.expect(session.monitors.takeExit(pids[0]) == null);
    try testing.expect(tasks.whereis("a") == null and tasks.whereis("b") != null);
    session.monitors.clear();
    session.outputs.discard();
}

test "output failure drops the claimed reply credit and unknown result fails closed" {
    const tasks = try Runtime.create(testing.allocator, io, .{ "a", "b" });
    defer tasks.deinit() catch unreachable;
    defer _ = tasks.shutdown();
    var session = Session.init(tasks, &peer, pids, 1);
    var output: [1]u8 = undefined;
    var writer = std.Io.Writer.fixed(&output);
    var hash = [_]etf.Term{ .{ .atom = "hash" }, .{ .binary = "abc" } };
    try request(&session, pids[0], .{ .tuple = &hash }, &writer);
    const result = (try tasks.nextResult()).?;
    try testing.expectError(error.WriteFailed, session.result(result, &writer));
    try testing.expectError(error.UnknownCompletion, session.result(result, &writer));
    for (0..10) |_| _ = try session.outputs.reserve();
    try testing.expectError(error.WouldBlock, session.outputs.reserve());
    session.outputs.discard();
}

test "stop sends 64 bounded monitor exits while sibling work remains pending" {
    var control = @import("task_runtime_test.zig").Control{ .actor = 1 };
    const tasks = try Runtime.create(testing.allocator, io, .{ "a", "b" });
    defer tasks.deinit() catch unreachable;
    defer _ = tasks.shutdown();
    defer control.release.set(io);
    tasks.control = &control;
    var session = Session.init(tasks, &peer, pids, 1);
    var buffer: [16384]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    for (0..64) |i| {
        var ref = reference;
        ref.ids[0] = @intCast(i + 1);
        var fields = [_]etf.Term{ .{ .integer = protocol.monitor.monitor_p }, .{ .pid = from }, .{ .pid = pids[0] }, .{ .reference = ref } };
        try deliver(&session, &.{ .tuple = &fields }, null, &writer);
    }
    try testing.expectEqual(@as(usize, 0), writer.buffered().len);
    var hash = [_]etf.Term{ .{ .atom = "hash" }, .{ .binary = "abc" } };
    try request(&session, pids[1], .{ .tuple = &hash }, &writer);
    try control.entered.waitTimeout(io, .{ .duration = .{ .raw = .fromSeconds(5), .clock = .awake } });
    try request(&session, pids[0], .{ .atom = "stop" }, &writer);
    const frames = writer.buffered();
    const first_len = std.mem.readInt(u32, frames[0..4], .big) + 4;
    var stopped = try decodeReply(frames[0..first_len]);
    defer stopped.deinit(testing.allocator);
    try testing.expectEqualStrings("ok", stopped.tuple[1].atom);
    var offset: usize = first_len;
    var seen: [64]bool = @splat(false);
    while (offset < frames.len) {
        const len = std.mem.readInt(u32, frames[offset..][0..4], .big) + 4;
        var packet = try dist.decodePacket(testing.allocator, frames[offset..][0..len], worker.limits);
        defer packet.deinit(testing.allocator);
        const exit = try protocol.monitor.parse(&packet.message.control);
        try testing.expect(exit.target.pid.eql(pids[0]));
        try testing.expectEqualStrings("normal", exit.reason.?.atom);
        const id = exit.reference.ids[0];
        try testing.expect(id >= 1 and id <= 64 and !seen[id - 1]);
        seen[id - 1] = true;
        offset += len;
    }
    for (seen) |received| try testing.expect(received);
    try testing.expect(session.monitors.takeExit(pids[0]) == null);
    control.release.set(io);
    writer = .fixed(&buffer);
    try session.result((try tasks.nextResult()).?, &writer);
    var reply = try decodeReply(writer.buffered());
    defer reply.deinit(testing.allocator);
    try testing.expectEqualStrings("ok", reply.tuple[1].tuple[0].atom);
    try testing.expectEqualStrings("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", &std.fmt.bytesToHex(reply.tuple[1].tuple[1].binary[0..32].*, .lower));
    session.outputs.discard();
}

test "failed monitor output does not undo actor stop or replay subscriptions" {
    const tasks = try Runtime.create(testing.allocator, io, .{ "a", "b" });
    defer tasks.deinit() catch unreachable;
    defer _ = tasks.shutdown();
    var session = Session.init(tasks, &peer, pids, 1);
    var scratch: [16384]u8 = undefined;
    var sink: [16384]u8 = undefined;
    var writer = std.Io.Writer.fixed(&sink);
    for (0..3) |i| {
        var ref = reference;
        ref.ids[0] = @intCast(i + 1);
        var fields = [_]etf.Term{ .{ .integer = protocol.monitor.monitor_p }, .{ .pid = from }, .{ .pid = pids[0] }, .{ .reference = ref } };
        try deliver(&session, &.{ .tuple = &fields }, null, &writer);
    }
    const stop_reply = try @import("wire_encode.zig").reply(&scratch, from, reference, .ok);
    writer = .fixed(sink[0..stop_reply.len]);
    try testing.expectError(error.WriteFailed, request(&session, pids[0], .{ .atom = "stop" }, &writer));
    try testing.expectEqualSlices(u8, stop_reply, writer.buffered());
    try testing.expect(tasks.whereis("a") == null and tasks.whereis("b") != null);
    session.monitors.clear();
    session.outputs.discard();
    var fresh = Session.init(tasks, &peer, pids, 2);
    try testing.expect(fresh.monitors.takeExit(pids[0]) == null);
    fresh.outputs.discard();
}
