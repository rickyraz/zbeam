//! Internal decoder for the proposed M2b profile. Actions borrow the packet or
//! the owned payload in Parsed; neither may outlive its corresponding owner.
const std = @import("std");
const etf = @import("zbeam-etf");
const protocol = @import("zbeam-protocol");
const transport = @import("zbeam-transport");
const dist = protocol.distribution;
const worker = @import("worker.zig");

pub const Envelope = struct { to: etf.Pid, reference: etf.Reference };
pub const Action = union(enum) {
    tick,
    drop,
    monitor: protocol.monitor.Signal,
    discover: struct { envelope: Envelope, actor_id: ?u64 },
    hash: struct { envelope: Envelope, actor_id: u64, bytes: []const u8 },
    stop: struct { envelope: Envelope, actor_id: u64 },
    bad_request: Envelope,
};
pub const Parsed = struct {
    action: Action,
    payload: ?etf.Term = null,
    pub fn deinit(self: *Parsed, allocator: std.mem.Allocator) void {
        if (self.payload) |*payload| payload.deinit(allocator);
        self.* = undefined;
    }
};

pub fn parse(allocator: std.mem.Allocator, packet: *const dist.Packet, peer: *const transport.handshake_io.Peer, pids: [2]etf.Pid, running: [2]bool) !Parsed {
    if (packet.* == .tick) return .{ .action = .tick };
    const message = &packet.message;
    const control = &message.control;
    if (control.* != .tuple or control.tuple.len == 0 or control.tuple[0] != .integer) return error.InvalidControl;
    const opcode = control.tuple[0].integer;
    if (opcode == protocol.monitor.monitor_p or opcode == protocol.monitor.demonitor_p or opcode == protocol.monitor.monitor_p_exit) {
        if (peer.flags & worker.monitor_flags != worker.monitor_flags) return error.UnnegotiatedMonitor;
        if (message.payload_etf != null) return error.InvalidControl;
        return .{ .action = .{ .monitor = try protocol.monitor.parse(control) } };
    }
    var from: ?etf.Pid = null;
    var actor_id: ?u64 = null;
    const discovery = switch (opcode) {
        dist.reg_send => blk: {
            const route = try dist.regSendDestination(control);
            if (!std.mem.eql(u8, route.name, "zbeam_workers")) return .{ .action = .drop };
            from = route.from;
            break :blk true;
        },
        dist.send => blk: {
            const fields = control.tuple;
            if (fields.len != 3 or fields[1] != .atom or fields[2] != .pid) return error.InvalidControl;
            for (pids, running, 0..) |pid, live, i| if (live and pid.eql(fields[2].pid)) {
                actor_id = i + 1;
                break;
            };
            if (actor_id == null) return .{ .action = .drop };
            break :blk false;
        },
        else => return error.InvalidControl,
    };
    var payload = try message.decodePayload(allocator, worker.limits.etf);
    errdefer payload.deinit(allocator);
    if (payload != .tuple or payload.tuple.len != 3) return error.InvalidPayload;
    const fields = payload.tuple;
    if (fields[0] != .pid or fields[1] != .reference) return error.InvalidPayload;
    const reply_to = fields[0].pid;
    const ref = fields[1].reference;
    if (reply_to.creation != peer.creation or ref.creation != peer.creation or
        !std.mem.eql(u8, reply_to.node, peer.node_name) or !std.mem.eql(u8, ref.node, peer.node_name)) return error.UnexpectedPeer;
    if (from) |sender| if (!sender.eql(reply_to)) return error.UnexpectedPeer;
    const envelope = Envelope{ .to = reply_to, .reference = ref };
    const command = &fields[2];
    var action: Action = .{ .bad_request = envelope };
    if (discovery) {
        if (command.* == .tuple and command.tuple.len == 2 and atom(&command.tuple[0], "discover") and command.tuple[1] == .atom) {
            const name = command.tuple[1].atom;
            const id: ?u64 = if (std.mem.eql(u8, name, "a")) 1 else if (std.mem.eql(u8, name, "b")) 2 else null;
            action = .{ .discover = .{ .envelope = envelope, .actor_id = id } };
        }
    } else if (atom(command, "stop")) {
        action = .{ .stop = .{ .envelope = envelope, .actor_id = actor_id.? } };
    } else if (command.* == .tuple and command.tuple.len == 2 and atom(&command.tuple[0], "hash") and command.tuple[1] == .binary) {
        action = .{ .hash = .{ .envelope = envelope, .actor_id = actor_id.?, .bytes = command.tuple[1].binary } };
    }
    return .{ .action = action, .payload = payload };
}

fn atom(value: *const etf.Term, text: []const u8) bool {
    return value.* == .atom and std.mem.eql(u8, value.atom, text);
}

const testing = std.testing;
const local = "native@host";
const remote = "peer@host";
const test_peer = transport.handshake_io.Peer{ .node_name = remote, .creation = 2, .flags = worker.monitor_flags };
const test_from = etf.Pid{ .node = remote, .creation = 2, .id = 4, .serial = 0 };
const test_ref = etf.Reference{ .node = remote, .creation = 2, .ids = .{ 1, 0, 0, 0, 0 }, .len = 1 };
const test_pids = [2]etf.Pid{
    .{ .node = local, .creation = 1, .id = 1, .serial = 0 },
    .{ .node = local, .creation = 1, .id = 2, .serial = 0 },
};

fn makePacket(control: *const etf.Term, payload: ?*const etf.Term) !dist.Packet {
    const bytes = try dist.encodePacket(testing.allocator, control, payload);
    defer testing.allocator.free(bytes);
    // Decoded packet payload borrows bytes, so tests with payload encode directly.
    if (payload != null) return error.TestUnexpectedResult;
    return dist.decodePacket(testing.allocator, bytes, worker.limits);
}

test "discovery, hash and stop decode with authenticated correlated envelopes" {
    var hash = [_]etf.Term{ .{ .atom = "hash" }, .{ .binary = "abc" } };
    var discover = [_]etf.Term{ .{ .atom = "discover" }, .{ .atom = "b" } };
    const commands = [_]etf.Term{ .{ .tuple = &discover }, .{ .tuple = &hash }, .{ .atom = "stop" } };
    for (commands, 0..) |command, i| {
        var reg = [_]etf.Term{ .{ .integer = dist.reg_send }, .{ .pid = test_from }, .{ .atom = "" }, .{ .atom = "zbeam_workers" } };
        var send = [_]etf.Term{ .{ .integer = dist.send }, .{ .atom = "" }, .{ .pid = test_pids[1] } };
        var body = [_]etf.Term{ .{ .pid = test_from }, .{ .reference = test_ref }, command };
        const bytes = try dist.encodePacket(testing.allocator, &.{ .tuple = if (i == 0) &reg else &send }, &.{ .tuple = &body });
        defer testing.allocator.free(bytes);
        var packet = try dist.decodePacket(testing.allocator, bytes, worker.limits);
        defer packet.deinit(testing.allocator);
        var parsed = try parse(testing.allocator, &packet, &test_peer, test_pids, .{ true, true });
        defer parsed.deinit(testing.allocator);
        switch (i) {
            0 => try testing.expectEqual(@as(?u64, 2), parsed.action.discover.actor_id),
            1 => {
                try testing.expectEqual(@as(u64, 2), parsed.action.hash.actor_id);
                try testing.expectEqualStrings("abc", parsed.action.hash.bytes);
                try testing.expect(parsed.action.hash.envelope.reference.eql(test_ref));
            },
            2 => try testing.expectEqual(@as(u64, 2), parsed.action.stop.actor_id),
            else => unreachable,
        }
    }
}

test "stale routes drop before decoding and negotiated monitor controls parse" {
    var fields = [_]etf.Term{ .{ .integer = dist.send }, .{ .atom = "" }, .{ .pid = test_pids[0] } };
    var packet = try makePacket(&.{ .tuple = &fields }, null);
    defer packet.deinit(testing.allocator);
    var parsed = try parse(testing.allocator, &packet, &test_peer, test_pids, .{ false, true });
    defer parsed.deinit(testing.allocator);
    try testing.expect(parsed.action == .drop);
    var fields2 = [_]etf.Term{ .{ .integer = protocol.monitor.monitor_p }, .{ .pid = test_from }, .{ .pid = test_pids[1] }, .{ .reference = test_ref } };
    var monitor_packet = try makePacket(&.{ .tuple = &fields2 }, null);
    defer monitor_packet.deinit(testing.allocator);
    var result = try parse(testing.allocator, &monitor_packet, &test_peer, test_pids, .{ true, true });
    defer result.deinit(testing.allocator);
    try testing.expect(result.action == .monitor);
    var unsupported = test_peer;
    unsupported.flags = 0;
    try testing.expectError(error.UnnegotiatedMonitor, parse(testing.allocator, &monitor_packet, &unsupported, test_pids, .{ true, true }));
}

test "hash input limit and allocation failure release decoded payload" {
    var control = [_]etf.Term{ .{ .integer = dist.send }, .{ .atom = "" }, .{ .pid = test_pids[0] } };
    const binary = try testing.allocator.alloc(u8, 1024 * 1024 + 1);
    defer testing.allocator.free(binary);
    @memset(binary, 'a');
    var command = [_]etf.Term{ .{ .atom = "hash" }, .{ .binary = binary } };
    var body = [_]etf.Term{ .{ .pid = test_from }, .{ .reference = test_ref }, .{ .tuple = &command } };
    for (0..2) |i| {
        command[1] = .{ .binary = if (i == 0) binary[0 .. binary.len - 1] else binary };
        const bytes = try dist.encodePacket(testing.allocator, &.{ .tuple = &control }, &.{ .tuple = &body });
        defer testing.allocator.free(bytes);
        var packet = try dist.decodePacket(testing.allocator, bytes, worker.limits);
        defer packet.deinit(testing.allocator);
        if (i == 0) {
            for (0..8) |failure_index| {
                var failing = testing.FailingAllocator.init(testing.allocator, .{ .fail_index = failure_index });
                if (parse(failing.allocator(), &packet, &test_peer, test_pids, .{ true, true })) |value| {
                    var owned = value;
                    owned.deinit(failing.allocator());
                } else |err| {
                    try testing.expectEqual(error.OutOfMemory, err);
                }
                try testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
            }
            var parsed = try parse(testing.allocator, &packet, &test_peer, test_pids, .{ true, true });
            defer parsed.deinit(testing.allocator);
            try testing.expectEqual(@as(usize, 1024 * 1024), parsed.action.hash.bytes.len);
        } else {
            try testing.expectError(error.LimitExceeded, parse(testing.allocator, &packet, &test_peer, test_pids, .{ true, true }));
        }
    }
}

test "discovery rejects a spoofed envelope and reports unknown names" {
    var control = [_]etf.Term{ .{ .integer = dist.reg_send }, .{ .pid = test_from }, .{ .atom = "" }, .{ .atom = "zbeam_workers" } };
    var command = [_]etf.Term{ .{ .atom = "discover" }, .{ .atom = "unknown" } };
    var reply_to = test_from;
    reply_to.id += 1;
    var body = [_]etf.Term{ .{ .pid = reply_to }, .{ .reference = test_ref }, .{ .tuple = &command } };
    for (0..2) |i| {
        if (i == 1) body[0] = .{ .pid = test_from };
        const bytes = try dist.encodePacket(testing.allocator, &.{ .tuple = &control }, &.{ .tuple = &body });
        defer testing.allocator.free(bytes);
        var packet = try dist.decodePacket(testing.allocator, bytes, worker.limits);
        defer packet.deinit(testing.allocator);
        if (i == 0) {
            try testing.expectError(error.UnexpectedPeer, parse(testing.allocator, &packet, &test_peer, test_pids, .{ true, true }));
        } else {
            var parsed = try parse(testing.allocator, &packet, &test_peer, test_pids, .{ true, true });
            defer parsed.deinit(testing.allocator);
            try testing.expectEqual(@as(?u64, null), parsed.action.discover.actor_id);
        }
    }
}
