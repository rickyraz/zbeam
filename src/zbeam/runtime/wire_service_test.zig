const std = @import("std");
const etf = @import("zbeam-etf");
const protocol = @import("zbeam-protocol");
const transport = @import("zbeam-transport");
const service = @import("wire_service.zig");
const worker = @import("worker.zig");
const testing = std.testing;
const io = testing.io;

fn pair() !struct { std.Io.net.Stream, std.Io.net.Stream } {
    const address: std.Io.net.IpAddress = .{ .ip4 = .loopback(0) };
    var listener = try address.listen(io, .{ .reuse_address = true });
    defer listener.deinit(io);
    const client = try listener.socket.address.connect(io, .{ .mode = .stream });
    errdefer client.close(io);
    return .{ client, try listener.accept(io) };
}

fn drop(bytes: []u8, allocator: std.mem.Allocator) void {
    allocator.free(bytes);
}

fn serveAndClose(owner: *service.Service, stream: std.Io.net.Stream) !void {
    defer stream.close(io);
    return owner.servePeer(stream);
}

fn discover(stream: std.Io.net.Stream, name: []const u8, id: u32) !etf.Pid {
    const from = etf.Pid{ .node = "peer@host", .creation = 2, .id = 4, .serial = 0 };
    const ref = etf.Reference{ .node = from.node, .creation = 2, .ids = .{ id, 0, 0, 0, 0 }, .len = 1 };
    var control = [_]etf.Term{ .{ .integer = protocol.distribution.reg_send }, .{ .pid = from }, .{ .atom = "" }, .{ .atom = "zbeam_workers" } };
    var command = [_]etf.Term{ .{ .atom = "discover" }, .{ .atom = name } };
    var body = [_]etf.Term{ .{ .pid = from }, .{ .reference = ref }, .{ .tuple = &command } };
    const request = try protocol.distribution.encodePacket(testing.allocator, &.{ .tuple = &control }, &.{ .tuple = &body });
    defer testing.allocator.free(request);
    var writer = stream.writer(io, &.{});
    try transport.distribution_io.writePacket(&writer.interface, request);
    var reader = stream.reader(io, &.{});
    const bytes = try transport.deadline.run(io, testing.allocator, .fromSeconds(5), transport.distribution_io.readPacket, .{ testing.allocator, &reader.interface, worker.limits.max_packet_bytes }, drop);
    defer testing.allocator.free(bytes);
    var packet = try protocol.distribution.decodePacket(testing.allocator, bytes, worker.limits);
    defer packet.deinit(testing.allocator);
    var reply = try packet.message.decodePayload(testing.allocator, worker.limits.etf);
    defer reply.deinit(testing.allocator);
    try testing.expect(reply.tuple[0].reference.eql(ref));
    const pid = reply.tuple[1].tuple[1].pid;
    // Return a canonical node slice, not the soon-freed decoded payload.
    try testing.expectEqualStrings("native@host", pid.node);
    return .{ .node = "native@host", .id = pid.id, .serial = pid.serial, .creation = pid.creation };
}

test "authenticated sequential peers observe stable distinct service identities" {
    var owner = try service.Service.init(io, testing.allocator, .{ .node_name = "native@host", .cookie = "cookie", .creation = 1 });
    defer owner.deinit();
    try testing.expect(!owner.pids[0].eql(owner.pids[1]));
    {
        const streams = try pair();
        defer streams[0].close(io);
        var future = try io.concurrent(serveAndClose, .{ &owner, streams[1] });
        defer _ = future.cancel(io) catch {};
        try testing.expectError(error.EndOfStream, transport.handshake_io.initiate(streams[0], io, testing.allocator, .{
            .node_name = "peer@host",
            .cookie = "wrong",
            .creation = 2,
            .flags = protocol.flags.m1 | worker.monitor_flags,
            .challenge = 44,
            .timeout = .fromSeconds(5),
        }));
        try testing.expectError(error.InvalidDigest, future.await(io));
    }
    for (0..2) |_| {
        const streams = try pair();
        var client_open = true;
        defer if (client_open) streams[0].close(io);
        defer streams[1].close(io);
        var future = try io.concurrent(service.Service.servePeer, .{ &owner, streams[1] });
        defer _ = future.cancel(io) catch {};
        var peer = try transport.handshake_io.initiate(streams[0], io, testing.allocator, .{
            .node_name = "peer@host",
            .cookie = "cookie",
            .creation = 2,
            .flags = protocol.flags.m1 | worker.monitor_flags,
            .challenge = 44,
            .timeout = .fromSeconds(5),
        });
        defer peer.deinit(testing.allocator);
        try testing.expectEqualStrings("native@host", peer.node_name);
        try testing.expect((try discover(streams[0], "a", 1)).eql(owner.pids[0]));
        try testing.expect((try discover(streams[0], "b", 2)).eql(owner.pids[1]));
        streams[0].close(io);
        client_open = false;
        try testing.expectError(error.EndOfStream, future.await(io));
    }
    try testing.expectEqual(@as(u64, 3), owner.epoch);
}

test "identity is not published when either actor cannot start" {
    var failing = testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 0 });
    try testing.expectError(error.OutOfMemory, service.Service.init(io, failing.allocator(), .{ .node_name = "native@host", .cookie = "cookie", .creation = 1 }));
    try testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
    const Shim = struct {
        var calls: usize = 0;
        var reject: usize = 0;
        var joined: usize = 0;
        fn concurrent(userdata: ?*anyopaque, len: usize, alignment: std.mem.Alignment, context: []const u8, context_alignment: std.mem.Alignment, entry: *const fn (*const anyopaque, *anyopaque) void) std.Io.ConcurrentError!*std.Io.AnyFuture {
            calls += 1;
            if (calls == reject) return error.ConcurrencyUnavailable;
            return io.vtable.concurrent(userdata, len, alignment, context, context_alignment, entry);
        }
        fn cancel(userdata: ?*anyopaque, future: *std.Io.AnyFuture, result: []u8, alignment: std.mem.Alignment) void {
            io.vtable.cancel(userdata, future, result, alignment);
            joined += 1;
        }
    };
    var vtable = io.vtable.*;
    vtable.concurrent = Shim.concurrent;
    vtable.cancel = Shim.cancel;
    const context = std.Io{ .userdata = io.userdata, .vtable = &vtable };
    for (1..3) |reject| {
        Shim.calls = 0;
        Shim.reject = reject;
        Shim.joined = 0;
        var counted = testing.FailingAllocator.init(testing.allocator, .{});
        try testing.expectError(error.ConcurrencyUnavailable, service.Service.init(context, counted.allocator(), .{ .node_name = "native@host", .cookie = "cookie", .creation = 1 }));
        try testing.expectEqual(reject - 1, Shim.joined);
        try testing.expectEqual(counted.allocated_bytes, counted.freed_bytes);
    }
}
