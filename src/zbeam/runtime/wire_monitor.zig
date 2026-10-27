//! Internal M2b monitor bookkeeping; the connection owner serializes all calls.
//! Peer/service node slices must outlive the table and any emitted notification.
const std = @import("std");
const etf = @import("zbeam-etf");
const protocol = @import("zbeam-protocol");
const monitor = protocol.monitor;
const Target = monitor.Target;

pub const endpoint = "zbeam_workers";
pub const capacity = 64;
pub const Subscription = struct { watcher: etf.Pid, reference: etf.Reference, target: Target };

pub const Table = struct {
    peer_name: []const u8,
    peer_creation: u32,
    pids: [2]etf.Pid,
    slots: [capacity]?Subscription = @splat(null),

    /// A non-null return requests immediate noproc output while the decoded
    /// control is still alive; no slices from it are retained by the table.
    pub fn handle(self: *Table, signal: monitor.Signal, running: [2]bool) !?monitor.Signal {
        if (signal.kind == .exited) {
            if (!std.mem.eql(u8, signal.watcher.node, self.pids[0].node)) return error.UnexpectedPeer;
            if (signal.target == .pid and !self.peerPid(signal.target.pid)) return error.UnexpectedPeer;
            return null;
        }
        if (!self.peerPid(signal.watcher) or signal.reference.creation != self.peer_creation or
            !std.mem.eql(u8, signal.reference.node, self.peer_name)) return error.UnexpectedPeer;
        if (signal.target == .pid and !std.mem.eql(u8, signal.target.pid.node, self.pids[0].node)) return error.UnexpectedPeer;
        for (&self.slots) |*slot| {
            if (slot.*) |current| {
                if (!current.reference.eql(signal.reference)) continue;
                if (!current.watcher.eql(signal.watcher) or !current.target.eql(signal.target)) return error.InvalidControl;
                if (signal.kind == .demonitor) slot.* = null;
                return null;
            }
        }
        if (signal.kind == .demonitor) return null;
        const target: Target = switch (signal.target) {
            .name => |name| if (std.mem.eql(u8, name, endpoint)) .{ .name = endpoint } else return signal,
            .pid => |pid| blk: {
                for (self.pids, running) |candidate, live| {
                    if (live and candidate.eql(pid)) break :blk .{ .pid = candidate };
                }
                return signal;
            },
        };
        for (&self.slots) |*slot| {
            if (slot.* != null) continue;
            var watcher = signal.watcher;
            var reference = signal.reference;
            watcher.node = self.peer_name;
            reference.node = self.peer_name;
            slot.* = .{ .watcher = watcher, .reference = reference, .target = target };
            return null;
        }
        return error.MonitorLimit;
    }

    /// Removes exactly one matching PID subscription before it is written.
    pub fn takeExit(self: *Table, target: etf.Pid) ?Subscription {
        for (&self.slots) |*slot| {
            const current = slot.* orelse continue;
            if (current.target != .pid or !current.target.pid.eql(target)) continue;
            slot.* = null;
            return current;
        }
        return null;
    }

    pub fn clear(self: *Table) void {
        self.slots = @splat(null);
    }

    fn peerPid(self: *const Table, pid: etf.Pid) bool {
        return pid.creation == self.peer_creation and std.mem.eql(u8, pid.node, self.peer_name);
    }
};

const testing = std.testing;
const test_watcher = etf.Pid{ .node = "peer@host", .creation = 2, .id = 10, .serial = 0 };
const test_pids = [2]etf.Pid{
    .{ .node = "native@host", .creation = 1, .id = 1, .serial = 0 },
    .{ .node = "native@host", .creation = 1, .id = 2, .serial = 0 },
};

fn sample(kind: monitor.Kind, target: Target, id: u32) monitor.Signal {
    return .{ .kind = kind, .watcher = test_watcher, .target = target, .reference = .{ .node = test_watcher.node, .creation = 2, .ids = .{ id, 0, 0, 0, 0 }, .len = 1 } };
}

test "PID and endpoint monitors remain distinct across one actor stop" {
    var table = Table{ .peer_name = test_watcher.node, .peer_creation = 2, .pids = test_pids };
    try testing.expect((try table.handle(sample(.monitor, .{ .pid = test_pids[0] }, 1), .{ true, true })) == null);
    try testing.expect((try table.handle(sample(.monitor, .{ .pid = test_pids[1] }, 2), .{ true, true })) == null);
    try testing.expect((try table.handle(sample(.monitor, .{ .name = endpoint }, 3), .{ true, true })) == null);
    const exit = table.takeExit(test_pids[0]).?;
    try testing.expectEqual(@as(u32, 1), exit.reference.ids[0]);
    try testing.expect(table.takeExit(test_pids[0]) == null);
    try testing.expect((try table.handle(sample(.monitor, .{ .pid = test_pids[0] }, 4), .{ false, true })) != null);
    try testing.expect((try table.handle(sample(.demonitor, .{ .pid = test_pids[1] }, 2), .{ false, true })) == null);
    try testing.expect(table.takeExit(test_pids[1]) == null);
    var remaining: usize = 0;
    for (table.slots) |slot| if (slot != null) {
        remaining += 1;
    };
    try testing.expectEqual(@as(usize, 1), remaining);
    table.clear();
}

test "duplicate, conflict, unknown and authenticated identity checks" {
    var table = Table{ .peer_name = test_watcher.node, .peer_creation = 2, .pids = test_pids };
    const original = sample(.monitor, .{ .pid = test_pids[0] }, 7);
    try testing.expect((try table.handle(original, .{ true, true })) == null);
    try testing.expect((try table.handle(original, .{ true, true })) == null);
    try testing.expectError(error.InvalidControl, table.handle(sample(.monitor, .{ .pid = test_pids[1] }, 7), .{ true, true }));
    try testing.expect((try table.handle(sample(.monitor, .{ .name = "other" }, 8), .{ true, true })) != null);
    var bad = sample(.monitor, .{ .pid = test_pids[1] }, 9);
    bad.reference.creation += 1;
    try testing.expectError(error.UnexpectedPeer, table.handle(bad, .{ true, true }));
    bad = sample(.monitor, .{ .pid = test_pids[1] }, 9);
    bad.watcher.node = "spoof@host";
    try testing.expectError(error.UnexpectedPeer, table.handle(bad, .{ true, true }));
    table.clear();
}

test "stored monitor nodes are canonical and independent of the frame" {
    var table = Table{ .peer_name = test_watcher.node, .peer_creation = 2, .pids = test_pids };
    var peer_copy = [_]u8{ 'p', 'e', 'e', 'r', '@', 'h', 'o', 's', 't' };
    var service_copy = [_]u8{ 'n', 'a', 't', 'i', 'v', 'e', '@', 'h', 'o', 's', 't' };
    var request = sample(.monitor, .{ .pid = test_pids[0] }, 4);
    request.watcher.node = &peer_copy;
    request.reference.node = &peer_copy;
    request.target.pid.node = &service_copy;
    try testing.expect((try table.handle(request, .{ true, true })) == null);
    peer_copy[0] = 'x';
    service_copy[0] = 'x';
    const exit = table.takeExit(test_pids[0]).?;
    try testing.expectEqualStrings(test_watcher.node, exit.watcher.node);
    try testing.expectEqualStrings(test_watcher.node, exit.reference.node);
    try testing.expectEqualStrings(test_pids[0].node, exit.target.pid.node);
    table.clear();
}

test "both actors and endpoint share the same fixed 64-slot table" {
    var table = Table{ .peer_name = test_watcher.node, .peer_creation = 2, .pids = test_pids };
    for (0..capacity) |i| {
        const target: Target = if (i % 3 == 0) .{ .pid = test_pids[0] } else if (i % 3 == 1) .{ .pid = test_pids[1] } else .{ .name = endpoint };
        try testing.expect((try table.handle(sample(.monitor, target, @intCast(i + 1)), .{ true, true })) == null);
    }
    try testing.expectError(error.MonitorLimit, table.handle(sample(.monitor, .{ .pid = test_pids[1] }, 99), .{ true, true }));
    try testing.expect((try table.handle(sample(.demonitor, .{ .pid = test_pids[0] }, 1), .{ true, true })) == null);
    try testing.expect((try table.handle(sample(.monitor, .{ .pid = test_pids[1] }, 99), .{ true, true })) == null);
    table.clear();
}
