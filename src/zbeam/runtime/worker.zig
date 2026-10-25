//! One service-owned worker, not a scheduler. All operations are serialized.
const std = @import("std");
const etf = @import("zbeam-etf");
const protocol = @import("zbeam-protocol");
const transport = @import("zbeam-transport");
const dist = protocol.distribution;

pub const limits = dist.Limits{ .max_packet_bytes = 2 * 1024 * 1024, .etf = .{
    .max_binary_bytes = 1024 * 1024,
    .max_collection_len = 64,
    .max_depth = 16,
    .max_allocated_bytes = 4 * 1024 * 1024,
} };
pub const State = enum { starting, running, stopping, stopped };

pub const Worker = struct {
    pid: etf.Pid,
    state: State = .starting,

    pub fn start(self: *Worker) error{InvalidTransition}!void {
        if (self.state != .starting) return error.InvalidTransition;
        self.state = .running;
    }

    pub fn handle(self: *Worker, allocator: std.mem.Allocator, bytes: []const u8, peer: *const transport.handshake_io.Peer, writer: *std.Io.Writer) !void {
        var packet = try dist.decodePacket(allocator, bytes, limits);
        defer packet.deinit(allocator);
        if (packet == .tick) return transport.distribution_io.writePacket(writer, &dist.tickPacket());
        const message = &packet.message;
        const control = &message.control;
        if (control.* != .tuple or control.tuple.len == 0 or control.tuple[0] != .integer) return error.InvalidControl;
        var from: ?etf.Pid = null;
        const discovery = switch (control.tuple[0].integer) {
            dist.reg_send => blk: {
                const route = try dist.regSendDestination(control);
                if (!std.mem.eql(u8, route.name, "zbeam_worker")) return;
                from = route.from;
                break :blk true;
            },
            dist.send => blk: {
                const fields = control.tuple;
                if (fields.len != 3 or fields[1] != .atom or fields[2] != .pid) return error.InvalidControl;
                if (self.state != .running or !self.pid.eql(fields[2].pid)) return;
                break :blk false;
            },
            else => return error.InvalidControl,
        };
        var payload = try message.decodePayload(allocator, limits.etf);
        defer payload.deinit(allocator);
        if (payload != .tuple or payload.tuple.len != 3) return error.InvalidPayload;
        const fields = payload.tuple;
        if (fields[0] != .pid or fields[1] != .reference) return error.InvalidPayload;
        const reply_to = fields[0].pid;
        const reference = fields[1].reference;
        if (!peerPid(reply_to, peer) or !std.mem.eql(u8, reference.node, peer.node_name) or reference.creation != peer.creation) return error.UnexpectedPeer;
        if (from) |sender| if (!sender.eql(reply_to)) return error.UnexpectedPeer;
        const command = &fields[2];
        if (discovery) {
            if (!atom(command, "discover")) return replyError(allocator, writer, reply_to, reference, "bad_request");
            if (self.state != .running) return replyError(allocator, writer, reply_to, reference, "noproc");
            var result = [_]etf.Term{ .{ .atom = "ok" }, .{ .pid = self.pid } };
            return reply(allocator, writer, reply_to, reference, &.{ .tuple = &result });
        }
        if (atom(command, "stop")) {
            self.state = .stopping;
            defer self.state = .stopped;
            return reply(allocator, writer, reply_to, reference, &.{ .atom = "ok" });
        }
        if (command.* == .tuple and command.tuple.len == 2 and atom(&command.tuple[0], "hash") and command.tuple[1] == .binary) {
            var digest: [32]u8 = undefined;
            std.crypto.hash.sha2.Sha256.hash(command.tuple[1].binary, &digest, .{});
            var result = [_]etf.Term{ .{ .atom = "ok" }, .{ .binary = &digest } };
            return reply(allocator, writer, reply_to, reference, &.{ .tuple = &result });
        }
        return replyError(allocator, writer, reply_to, reference, "bad_request");
    }
};

fn peerPid(pid: etf.Pid, peer: *const transport.handshake_io.Peer) bool {
    return pid.creation == peer.creation and std.mem.eql(u8, pid.node, peer.node_name);
}

fn atom(term: *const etf.Term, text: []const u8) bool {
    return term.* == .atom and std.mem.eql(u8, term.atom, text);
}

fn emit(allocator: std.mem.Allocator, writer: *std.Io.Writer, control: *const etf.Term, payload: ?*const etf.Term) !void {
    const bytes = try dist.encodePacket(allocator, control, payload);
    defer allocator.free(bytes);
    try transport.distribution_io.writePacket(writer, bytes);
}

fn reply(allocator: std.mem.Allocator, writer: *std.Io.Writer, to: etf.Pid, reference: etf.Reference, result: *const etf.Term) !void {
    var control = [_]etf.Term{ .{ .integer = dist.send }, .{ .atom = "" }, .{ .pid = to } };
    var fields = [_]etf.Term{ .{ .reference = reference }, result.* };
    return emit(allocator, writer, &.{ .tuple = &control }, &.{ .tuple = &fields });
}

fn replyError(allocator: std.mem.Allocator, writer: *std.Io.Writer, to: etf.Pid, reference: etf.Reference, reason: []const u8) !void {
    var result = [_]etf.Term{ .{ .atom = "error" }, .{ .atom = reason } };
    return reply(allocator, writer, to, reference, &.{ .tuple = &result });
}

test {
    _ = @import("worker_test.zig");
}
