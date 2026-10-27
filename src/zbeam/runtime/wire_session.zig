//! Internal single-owner dispatcher; no socket or public service is enabled.
//! Peer/service names and all external API users outlive the session.
const std = @import("std");
const etf = @import("zbeam-etf");
const transport = @import("zbeam-transport");
const protocol = @import("zbeam-protocol");
const Runtime = @import("task_runtime.zig");
const gate = @import("wire_gate.zig");
const route = @import("wire_route.zig");
const output = @import("wire_output.zig");
const monitor = @import("wire_monitor.zig");
const encode = @import("wire_encode.zig");
const worker = @import("worker.zig");

pub const Session = struct {
    tasks: *Runtime,
    peer: *const transport.handshake_io.Peer,
    pids: [2]etf.Pid,
    outputs: output.Table,
    monitors: monitor.Table,

    pub fn init(tasks: *Runtime, peer: *const transport.handshake_io.Peer, pids: [2]etf.Pid, epoch: u64) Session {
        return .{ .tasks = tasks, .peer = peer, .pids = pids, .outputs = .{ .peer_name = peer.node_name, .peer_creation = peer.creation, .epoch = epoch }, .monitors = .{ .peer_name = peer.node_name, .peer_creation = peer.creation, .pids = pids } };
    }

    fn running(self: *Session) [2]bool {
        return .{ self.tasks.whereis("a") != null, self.tasks.whereis("b") != null };
    }

    /// Caller owns/frees bytes and serializes writes. The reader is already
    /// joined; frame reservations are consumed or released on every path.
    pub fn process(self: *Session, frame: *gate.Frame, allocator: std.mem.Allocator, bytes: []const u8, writer: *std.Io.Writer) !void {
        defer if (frame.active) frame.release();
        var packet = try protocol.distribution.decodePacket(allocator, bytes, worker.limits);
        defer packet.deinit(allocator);
        var parsed = try route.parse(allocator, &packet, self.peer, self.pids, self.running());
        defer parsed.deinit(allocator);
        switch (parsed.action) {
            .tick => try transport.distribution_io.writePacket(writer, &protocol.distribution.tickPacket()),
            .drop => {},
            .bad_request => |envelope| try sendReply(writer, envelope, .{ .failure = .bad_request }),
            .discover => |request| {
                const id = request.actor_id orelse return sendReply(writer, request.envelope, .{ .failure = .noproc });
                const slot: usize = @intCast(id - 1);
                if (!self.running()[slot]) return sendReply(writer, request.envelope, .{ .failure = .noproc });
                try sendReply(writer, request.envelope, .{ .pid = self.pids[slot] });
            },
            .hash => |request| {
                _ = frame.send(request.actor_id, request.bytes, request.envelope.to, request.envelope.reference) catch |err| switch (err) {
                    error.ActorStopped => return,
                    else => return err,
                };
            },
            .stop => |request| {
                const index: usize = @intCast(request.actor_id - 1);
                const exit = try self.tasks.stopAndJoin(request.actor_id);
                const failed = exit == .handler_failed;
                try sendReply(writer, request.envelope, if (failed) .{ .failure = .handler_failed } else .ok);
                while (self.monitors.takeExit(self.pids[index])) |subscription| {
                    try sendExit(writer, subscription.target, subscription.watcher, subscription.reference, if (failed) .handler_failed else .normal);
                }
            },
            .monitor => |signal| {
                if (try self.monitors.handle(signal, self.running())) |unknown| {
                    try sendExit(writer, unknown.target, unknown.watcher, unknown.reference, .noproc);
                }
            },
        }
    }

    /// Holds the result's output credit through flush or explicit drop.
    pub fn result(self: *Session, value: Runtime.Result, writer: *std.Io.Writer) !void {
        const delivery = self.outputs.beginWrite(self.outputs.epoch, value.request_id) orelse return error.UnknownCompletion;
        defer self.outputs.finishWrite(delivery.ticket);
        const encoded: encode.Result = switch (value.outcome) {
            .digest => |digest| .{ .digest = digest },
            .stopped => .{ .failure = .stopped },
            .canceled => .{ .failure = .canceled },
            .handler_failed => .{ .failure = .handler_failed },
        };
        if (value.outcome == .handler_failed) _ = try self.tasks.stopAndJoin(value.actor_id);
        try sendReply(writer, .{ .to = delivery.to, .reference = delivery.reference }, encoded);
        if (value.outcome == .handler_failed) {
            const index: usize = @intCast(value.actor_id - 1);
            while (self.monitors.takeExit(self.pids[index])) |subscription| {
                try sendExit(writer, subscription.target, subscription.watcher, subscription.reference, .handler_failed);
            }
        }
    }
};

fn sendReply(writer: *std.Io.Writer, envelope: route.Envelope, result_value: encode.Result) !void {
    var scratch: [encode.scratch_bytes]u8 = undefined;
    const bytes = try encode.reply(&scratch, envelope.to, envelope.reference, result_value);
    try transport.distribution_io.writePacket(writer, bytes);
}

fn sendExit(writer: *std.Io.Writer, target: protocol.monitor.Target, to: etf.Pid, ref: etf.Reference, reason: encode.Reason) !void {
    var scratch: [encode.scratch_bytes]u8 = undefined;
    const bytes = try encode.monitorExit(&scratch, target, to, ref, reason);
    try transport.distribution_io.writePacket(writer, bytes);
}

test {
    _ = @import("wire_session_test.zig");
}
