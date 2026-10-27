//! Internal pre-read ownership gate. The connection owner serializes table and
//! frame operations and joins its reader before releasing a frame reservation.
const std = @import("std");
const actor = @import("zbeam-actor");
const etf = @import("zbeam-etf");
const transport = @import("zbeam-transport");
const Runtime = @import("task_runtime.zig");
const admission = @import("wire_admission.zig");
const output = @import("wire_output.zig");
const assert = std.debug.assert;

pub const Frame = struct {
    lease: admission.Lease,
    outputs: *output.Table,
    ticket: usize,
    attempted: bool = false,
    read_ok: bool = false,
    active: bool = true,

    /// Performs one unbuffered read; any failure is terminal for the stream.
    /// The owner frees returned bytes and releases this frame after joining the
    /// reader, including on error/cancellation. No lifecycle gate is held here.
    pub fn read(self: *Frame, allocator: std.mem.Allocator, reader: *std.Io.Reader, max_bytes: u32) ![]u8 {
        assert(self.active);
        if (self.attempted) return error.AlreadyRead;
        self.attempted = true;
        var demand = actor.Demand.init(1);
        const bytes = try transport.distribution_io.readDemandedPacket(allocator, reader, max_bytes, &demand);
        self.read_ok = true;
        return bytes;
    }

    /// Controls/unknown targets release after their output finishes or drops.
    pub fn release(self: *Frame) void {
        assert(self.active);
        self.lease.release();
        self.outputs.cancel(self.ticket);
        self.active = false;
    }

    /// Validate correlation first, then transfer one actor reservation. Caller
    /// serializes result collection with bind; after success the output credit
    /// remains pending until a later write/drop finishes.
    pub fn send(self: *Frame, id: u64, bytes: []const u8, to: etf.Pid, ref: etf.Reference) !u64 {
        assert(self.active);
        if (!self.read_ok) return error.FrameNotRead;
        self.outputs.prepare(self.ticket, to, ref) catch |err| {
            self.release();
            return err;
        };
        const request = self.lease.send(id, bytes) catch |err| {
            self.outputs.cancel(self.ticket);
            self.active = false;
            return err;
        };
        self.outputs.bind(self.ticket, request);
        self.active = false;
        return request;
    }
};

/// Output and all currently routable actors are reserved before any read.
/// Failure rolls the output credit back and performs no read or allocation.
pub fn begin(tasks: *Runtime, outputs: *output.Table) !Frame {
    const ticket = try outputs.reserve();
    errdefer outputs.cancel(ticket);
    const lease = try admission.acquire(tasks);
    return .{ .lease = lease, .outputs = outputs, .ticket = ticket };
}

const testing = std.testing;
const io = testing.io;
const peer = "peer@host";
const test_pid = etf.Pid{ .node = peer, .creation = 1, .id = 2, .serial = 0 };
const test_ref = etf.Reference{ .node = peer, .creation = 1, .len = 1 };
const Reader = struct {
    interface: std.Io.Reader = .{ .vtable = &.{ .stream = stream }, .buffer = &.{}, .seek = 0, .end = 0 },
    bytes: []const u8,
    calls: usize = 0,

    fn stream(interface: *std.Io.Reader, writer: *std.Io.Writer, limit: std.Io.Limit) std.Io.Reader.StreamError!usize {
        const self: *Reader = @fieldParentPtr("interface", interface);
        self.calls += 1;
        if (self.bytes.len == 0) return error.EndOfStream;
        const n = try writer.write(self.bytes[0..limit.minInt(self.bytes.len)]);
        self.bytes = self.bytes[n..];
        return n;
    }
};

fn tryRead(tasks: *Runtime, table: *output.Table, allocator: std.mem.Allocator, reader: *std.Io.Reader) ![]u8 {
    var frame = try begin(tasks, table);
    defer frame.release();
    return frame.read(allocator, reader, 1024);
}

test "full output or actor capacity causes zero read and no frame allocation" {
    var counted = testing.FailingAllocator.init(testing.allocator, .{});
    {
        var control = @import("task_runtime_test.zig").Control{ .actor = 1 };
        const tasks = try Runtime.create(counted.allocator(), io, .{ "a", "b" });
        defer tasks.deinit() catch unreachable;
        defer _ = tasks.shutdown();
        tasks.control = &control;
        var table = output.Table{ .peer_name = peer, .peer_creation = 1, .epoch = 1 };
        var source = Reader{ .bytes = &.{ 0, 0, 0, 0 } };
        var tickets: [output.capacity]usize = undefined;
        for (&tickets) |*ticket| ticket.* = try table.reserve();
        const allocations = counted.alloc_index;
        try testing.expectError(error.WouldBlock, tryRead(tasks, &table, counted.allocator(), &source.interface));
        try testing.expectEqual(@as(usize, 0), source.calls);
        try testing.expectEqual(allocations, counted.alloc_index);
        for (tickets) |ticket| table.cancel(ticket);
        _ = try tasks.trySend(2, "held");
        try control.entered.waitTimeout(io, .{ .duration = .{ .raw = .fromSeconds(5), .clock = .awake } });
        for (0..4) |_| _ = try tasks.trySend(2, "queued");
        const next = counted.alloc_index;
        try testing.expectError(error.WouldBlock, tryRead(tasks, &table, counted.allocator(), &source.interface));
        try testing.expectEqual(@as(usize, 0), source.calls);
        try testing.expectEqual(next, counted.alloc_index);
        const reusable = try table.reserve();
        table.cancel(reusable);
        control.release.set(io);
    }
    try testing.expectEqual(counted.allocated_bytes, counted.freed_bytes);
}

test "one unbuffered frame transfers work and retains output until write" {
    const tasks = try Runtime.create(testing.allocator, io, .{ "a", "b" });
    defer tasks.deinit() catch unreachable;
    defer _ = tasks.shutdown();
    var table = output.Table{ .peer_name = peer, .peer_creation = 1, .epoch = 9 };
    var source = Reader{ .bytes = &.{ 0, 0, 0, 1, 112, 0, 0, 0, 0 } };
    var frame = try begin(tasks, &table);
    const packet = try frame.read(testing.allocator, &source.interface, 1024);
    defer testing.allocator.free(packet);
    try testing.expectEqualSlices(u8, &.{ 0, 0, 0, 1, 112 }, packet);
    try testing.expectError(error.AlreadyRead, frame.read(testing.allocator, &source.interface, 1024));
    try testing.expectEqual(@as(usize, 4), source.bytes.len);
    const id = try frame.send(1, "abc", test_pid, test_ref);
    const result = (try tasks.nextResult()).?;
    try testing.expectEqual(id, result.request_id);
    try testing.expect(table.beginWrite(8, id) == null);
    const delivery = table.beginWrite(9, id).?;
    table.finishWrite(delivery.ticket);
    table.discard();
}

test "read or correlation failure releases all capacity without acceptance" {
    const tasks = try Runtime.create(testing.allocator, io, .{ "a", "b" });
    defer tasks.deinit() catch unreachable;
    defer _ = tasks.shutdown();
    var table = output.Table{ .peer_name = peer, .peer_creation = 1, .epoch = 1 };
    var partial = Reader{ .bytes = &.{ 0, 0 } };
    var frame = try begin(tasks, &table);
    try testing.expectError(error.Truncated, frame.read(testing.allocator, &partial.interface, 1024));
    frame.release();
    var source = Reader{ .bytes = &.{ 0, 0, 0, 0 } };
    var next = try begin(tasks, &table);
    const packet = try next.read(testing.allocator, &source.interface, 1024);
    testing.allocator.free(packet);
    var bad = test_pid;
    bad.creation += 1;
    try testing.expectError(error.UnexpectedPeer, next.send(1, "abc", bad, test_ref));
    var last = try begin(tasks, &table);
    last.release();
    table.discard();
}
