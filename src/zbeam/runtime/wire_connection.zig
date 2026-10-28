//! Internal single-peer connection loop used by the two-worker service.
//! The caller owns peer identity, task runtime and sequential connection epochs.
const std = @import("std");
const etf = @import("zbeam-etf");
const transport = @import("zbeam-transport");
const Runtime = @import("task_runtime.zig");
const gate = @import("wire_gate.zig");
const Session = @import("wire_session.zig").Session;
const worker = @import("worker.zig");
const Event = union(enum) { read: anyerror![]u8, result: anyerror!?Runtime.Result };

pub const Config = struct {
    frame_timeout: ?std.Io.Duration = .fromSeconds(90),
    write_timeout: ?std.Io.Duration = .fromSeconds(5),
};

pub fn serve(io: std.Io, allocator: std.mem.Allocator, stream: std.Io.net.Stream, peer: *const transport.handshake_io.Peer, tasks: *Runtime, pids: [2]etf.Pid, epoch: u64, config: Config) !void {
    var storage: [2]Event = undefined;
    var state = State{
        .io = io,
        .allocator = allocator,
        .reader = stream.reader(io, &.{}),
        .writer = stream.writer(io, &.{}),
        .session = Session.init(tasks, peer, pids, epoch),
        .select = std.Io.Select(Event).init(io, &storage),
        .config = config,
    };
    const outcome = state.run();
    try state.close();
    return outcome;
}

const State = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    reader: std.Io.net.Stream.Reader,
    writer: std.Io.net.Stream.Writer,
    session: Session,
    select: std.Io.Select(Event),
    config: Config,
    frame: ?gate.Frame = null,
    reading: bool = false,
    collecting: bool = false,

    fn run(self: *State) !void {
        while (true) {
            if (!self.reading) {
                self.frame = gate.begin(self.session.tasks, &self.session.outputs) catch |err| switch (err) {
                    error.WouldBlock => null,
                    else => return err,
                };
                if (self.frame) |*frame| {
                    try self.select.concurrent(.read, readFrame, .{ self.io, self.allocator, frame, &self.reader.interface, self.config.frame_timeout });
                    self.reading = true;
                }
            }
            if (!self.collecting and self.pending() != 0) {
                try self.select.concurrent(.result, Runtime.nextResult, .{self.session.tasks});
                self.collecting = true;
            }
            if (!self.reading and !self.collecting) return error.NoProgress;
            switch (try self.select.await()) {
                .read => |outcome| {
                    self.reading = false;
                    const bytes = outcome catch |err| return if (err == error.ReadFailed) self.reader.err orelse err else err;
                    defer self.allocator.free(bytes);
                    try transport.deadline.run(self.io, self.allocator, self.config.write_timeout, Session.process, .{ &self.session, &self.frame.?, self.allocator, bytes, &self.writer.interface }, transport.deadline.dropVoid);
                    self.frame = null;
                },
                .result => |outcome| {
                    self.collecting = false;
                    const result = (try outcome) orelse return error.MissingCompletion;
                    try self.deliver(result);
                },
            }
        }
    }

    fn deliver(self: *State, result: Runtime.Result) !void {
        transport.deadline.run(self.io, self.allocator, self.config.write_timeout, Session.result, .{ &self.session, result, &self.writer.interface }, transport.deadline.dropVoid) catch |err| {
            // A launch failure can precede Session.result's credit cleanup.
            _ = try self.drop(result);
            return err;
        };
    }

    fn pending(self: *State) usize {
        var count: usize = 0;
        for (self.session.outputs.entries) |entry| if (entry.stage == .pending) {
            count += 1;
        };
        return count;
    }

    /// Join reader/collector before peer teardown, then discard this epoch's
    /// completed work. No new peer is accepted while old results remain.
    fn close(self: *State) !void {
        const previous = self.io.swapCancelProtection(.blocked);
        defer _ = self.io.swapCancelProtection(previous);
        var unknown = false;
        var collector_error: ?anyerror = null;
        while (self.select.cancel()) |event| switch (event) {
            .read => |result| if (result) |bytes| self.allocator.free(bytes) else |_| {},
            .result => |result| if (result) |maybe| {
                if (maybe) |value| if (!try self.drop(value)) {
                    unknown = true;
                };
            } else |err| {
                if (err != error.Canceled) collector_error = err;
            },
        };
        if (self.frame) |*frame| if (frame.active) frame.release();
        while (self.pending() != 0) {
            const value = (try self.session.tasks.nextResult()) orelse return error.MissingCompletion;
            if (!try self.drop(value)) unknown = true;
        }
        self.session.outputs.discard();
        self.session.monitors.clear();
        if (collector_error) |err| return err;
        if (unknown) return error.UnknownCompletion;
    }

    fn drop(self: *State, value: Runtime.Result) !bool {
        if (value.outcome == .handler_failed) _ = try self.session.tasks.stopAndJoin(value.actor_id);
        const delivery = self.session.outputs.beginWrite(self.session.outputs.epoch, value.request_id) orelse return false;
        self.session.outputs.finishWrite(delivery.ticket);
        return true;
    }
};

fn readFrame(io: std.Io, allocator: std.mem.Allocator, frame: *gate.Frame, reader: *std.Io.Reader, timeout: ?std.Io.Duration) ![]u8 {
    return transport.deadline.run(io, allocator, timeout, gate.Frame.read, .{ frame, allocator, reader, worker.limits.max_packet_bytes }, dropPacket);
}

fn dropPacket(bytes: []u8, allocator: std.mem.Allocator) void {
    allocator.free(bytes);
}

test {
    _ = @import("wire_connection_test.zig");
}

test "writer launch failure drops the already collected result before draining" {
    const testing = std.testing;
    const Shim = struct {
        fn reject(_: ?*anyopaque, _: *std.Io.Group, _: []const u8, _: std.mem.Alignment, _: *const fn (*const anyopaque) void) std.Io.ConcurrentError!void {
            return error.ConcurrencyUnavailable;
        }
    };
    var vtable = testing.io.vtable.*;
    vtable.groupConcurrent = Shim.reject;
    const io = std.Io{ .userdata = testing.io.userdata, .vtable = &vtable };
    const tasks = try Runtime.create(testing.allocator, testing.io, .{ "a", "b" });
    defer tasks.deinit() catch unreachable;
    defer _ = tasks.shutdown();
    const peer = transport.handshake_io.Peer{ .node_name = "peer@host", .creation = 2, .flags = worker.monitor_flags };
    const pid = etf.Pid{ .node = peer.node_name, .creation = 2, .id = 1, .serial = 0 };
    const reference = etf.Reference{ .node = peer.node_name, .creation = 2, .ids = .{ 1, 0, 0, 0, 0 }, .len = 1 };
    var storage: [2]Event = undefined;
    var state = State{
        .io = io,
        .allocator = testing.allocator,
        // The rejected writer task never accesses either stream interface.
        .reader = undefined,
        .writer = undefined,
        .session = Session.init(tasks, &peer, .{ pid, pid }, 1),
        .select = std.Io.Select(Event).init(io, &storage),
        .config = .{},
    };
    const ticket = try state.session.outputs.reserve();
    try state.session.outputs.prepare(ticket, pid, reference);
    state.session.outputs.bind(ticket, try tasks.trySend(1, "abc"));
    const result = (try tasks.nextResult()).?;
    try testing.expectError(error.ConcurrencyUnavailable, state.deliver(result));
    try testing.expectEqual(@as(usize, 0), state.pending());
    try state.close();
    try testing.expect(!tasks.wire_reservation_active);
}
