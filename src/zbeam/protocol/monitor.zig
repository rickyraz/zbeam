//! Distributed monitor control shapes; all returned slices borrow the term.
const std = @import("std");
const etf = @import("zbeam-etf");

pub const monitor_p: i64 = 19;
pub const demonitor_p: i64 = 20;
pub const monitor_p_exit: i64 = 21;
pub const Kind = enum { monitor, demonitor, exited };
pub const Target = union(enum) {
    pid: etf.Pid,
    name: []const u8,

    pub fn eql(self: Target, other: Target) bool {
        return switch (self) {
            .pid => |pid| other == .pid and pid.eql(other.pid),
            .name => |name| other == .name and std.mem.eql(u8, name, other.name),
        };
    }

    pub fn term(self: Target) etf.Term {
        return switch (self) {
            .pid => |pid| .{ .pid = pid },
            .name => |name| .{ .atom = name },
        };
    }
};
pub const Signal = struct {
    kind: Kind,
    watcher: etf.Pid,
    target: Target,
    reference: etf.Reference,
    reason: ?*const etf.Term = null,
};

pub fn parse(control: *const etf.Term) error{InvalidControl}!Signal {
    if (control.* != .tuple) return error.InvalidControl;
    const fields = control.tuple;
    if (fields.len < 4 or fields[0] != .integer) return error.InvalidControl;
    const kind: Kind = switch (fields[0].integer) {
        monitor_p => .monitor,
        demonitor_p => .demonitor,
        monitor_p_exit => .exited,
        else => return error.InvalidControl,
    };
    if (fields.len != (if (kind == .exited) @as(usize, 5) else @as(usize, 4))) return error.InvalidControl;
    const watcher_index: usize = if (kind == .exited) 2 else 1;
    const target_index: usize = if (kind == .exited) 1 else 2;
    if (fields[watcher_index] != .pid or fields[3] != .reference) return error.InvalidControl;
    const target: Target = switch (fields[target_index]) {
        .pid => |pid| .{ .pid = pid },
        .atom => |name| .{ .name = name },
        else => return error.InvalidControl,
    };
    return .{ .kind = kind, .watcher = fields[watcher_index].pid, .target = target, .reference = fields[3].reference, .reason = if (kind == .exited) &fields[4] else null };
}

test "monitor controls validate opcode arity PID and named target fields" {
    const pid = etf.Pid{ .node = "n@h", .id = 1, .serial = 0, .creation = 1 };
    var fields = [_]etf.Term{ .{ .integer = monitor_p }, .{ .pid = pid }, .{ .pid = pid }, .{ .reference = .{ .node = "n@h", .creation = 1, .len = 1 } }, .{ .atom = "normal" } };
    for ([_]struct { op: i64, kind: Kind, len: usize }{
        .{ .op = monitor_p, .kind = .monitor, .len = 4 },
        .{ .op = demonitor_p, .kind = .demonitor, .len = 4 },
        .{ .op = monitor_p_exit, .kind = .exited, .len = 5 },
    }) |case| {
        fields[0] = .{ .integer = case.op };
        const index: usize = if (case.kind == .exited) 1 else 2;
        try std.testing.expectEqual(case.kind, (try parse(&.{ .tuple = fields[0..case.len] })).kind);
        fields[index] = .{ .atom = "endpoint" };
        try std.testing.expectEqualStrings("endpoint", (try parse(&.{ .tuple = fields[0..case.len] })).target.name);
        try std.testing.expectError(error.InvalidControl, parse(&.{ .tuple = fields[0 .. case.len - 1] }));
        fields[index] = .{ .pid = pid };
    }
    fields[0] = .{ .integer = monitor_p };
    fields[2] = .{ .integer = 1 };
    try std.testing.expectError(error.InvalidControl, parse(&.{ .tuple = fields[0..4] }));
    try std.testing.expectError(error.InvalidControl, parse(&.nil));
}
