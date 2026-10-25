//! PID-only distributed monitor controls; no monitor table or I/O policy.
const std = @import("std");
const etf = @import("zbeam-etf");

pub const monitor_p: i64 = 19;
pub const demonitor_p: i64 = 20;
pub const monitor_p_exit: i64 = 21;
pub const Kind = enum { monitor, demonitor, exited };
pub const Signal = struct {
    kind: Kind,
    from: etf.Pid,
    to: etf.Pid,
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
    if (fields[1] != .pid or fields[2] != .pid or fields[3] != .reference) return error.InvalidControl;
    return .{ .kind = kind, .from = fields[1].pid, .to = fields[2].pid, .reference = fields[3].reference, .reason = if (kind == .exited) &fields[4] else null };
}

test "monitor controls validate opcode arity and PID-only fields" {
    const pid = etf.Pid{ .node = "n@h", .id = 1, .serial = 0, .creation = 1 };
    var fields = [_]etf.Term{
        .{ .integer = monitor_p },                                     .{ .pid = pid },       .{ .pid = pid },
        .{ .reference = .{ .node = "n@h", .creation = 1, .len = 1 } }, .{ .atom = "normal" },
    };
    for ([_]struct { op: i64, kind: Kind, len: usize }{
        .{ .op = monitor_p, .kind = .monitor, .len = 4 },
        .{ .op = demonitor_p, .kind = .demonitor, .len = 4 },
        .{ .op = monitor_p_exit, .kind = .exited, .len = 5 },
    }) |case| {
        fields[0] = .{ .integer = case.op };
        try std.testing.expectEqual(case.kind, (try parse(&.{ .tuple = fields[0..case.len] })).kind);
        try std.testing.expectError(error.InvalidControl, parse(&.{ .tuple = fields[0 .. case.len - 1] }));
    }
    fields[0] = .{ .integer = monitor_p };
    fields[2] = .{ .atom = "unsupported_named_monitor" };
    try std.testing.expectError(error.InvalidControl, parse(&.{ .tuple = fields[0..4] }));
    try std.testing.expectError(error.InvalidControl, parse(&.nil));
}
