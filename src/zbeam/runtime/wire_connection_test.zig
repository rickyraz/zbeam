const std = @import("std");
const etf = @import("zbeam-etf");
const protocol = @import("zbeam-protocol");
const transport = @import("zbeam-transport");
const Runtime = @import("task_runtime.zig");
const connection = @import("wire_connection.zig");
const worker = @import("worker.zig");
const dist = protocol.distribution;
const testing = std.testing;
const io = testing.io;
const peer = transport.handshake_io.Peer{ .node_name = "peer@host", .creation = 2, .flags = worker.monitor_flags };
const from = etf.Pid{ .node = "peer@host", .creation = 2, .id = 4, .serial = 0 };
const pids = [2]etf.Pid{
    .{ .node = "native@host", .creation = 1, .id = 1, .serial = 0 },
    .{ .node = "native@host", .creation = 1, .id = 2, .serial = 0 },
};

fn reference(id: u32) etf.Reference {
    return .{ .node = peer.node_name, .creation = 2, .ids = .{ id, 0, 0, 0, 0 }, .len = 1 };
}

fn send(writer: *std.Io.Writer, to: etf.Pid, id: u32, payload: []const u8) !void {
    var control = [_]etf.Term{ .{ .integer = dist.send }, .{ .atom = "" }, .{ .pid = to } };
    var command = [_]etf.Term{ .{ .atom = "hash" }, .{ .binary = payload } };
    var body = [_]etf.Term{ .{ .pid = from }, .{ .reference = reference(id) }, .{ .tuple = &command } };
    const bytes = try dist.encodePacket(testing.allocator, &.{ .tuple = &control }, &.{ .tuple = &body });
    defer testing.allocator.free(bytes);
    try transport.distribution_io.writePacket(writer, bytes);
}

fn read(reader: *std.Io.Reader) !etf.Term {
    const bytes = try transport.deadline.run(io, testing.allocator, .fromSeconds(5), transport.distribution_io.readPacket, .{ testing.allocator, reader, worker.limits.max_packet_bytes }, drop);
    defer testing.allocator.free(bytes);
    var packet = try dist.decodePacket(testing.allocator, bytes, worker.limits);
    defer packet.deinit(testing.allocator);
    return packet.message.decodePayload(testing.allocator, worker.limits.etf);
}

fn drop(bytes: []u8, allocator: std.mem.Allocator) void {
    allocator.free(bytes);
}

fn expectDisconnect(result: anyerror!void) !void {
    if (result) |_| return error.TestUnexpectedResult else |err| {
        try testing.expect(err == error.EndOfStream or err == error.ConnectionResetByPeer or err == error.BrokenPipe or err == error.WriteFailed);
    }
}

fn pair() !struct { std.Io.net.Stream, std.Io.net.Stream } {
    const address: std.Io.net.IpAddress = .{ .ip4 = .loopback(0) };
    var server = try address.listen(io, .{ .reuse_address = true });
    defer server.deinit(io);
    const client = try server.socket.address.connect(io, .{ .mode = .stream });
    errdefer client.close(io);
    return .{ client, try server.accept(io) };
}

test "internal connection replies to both actors with exact correlation" {
    const tasks = try Runtime.create(testing.allocator, io, .{ "a", "b" });
    defer tasks.deinit() catch unreachable;
    defer _ = tasks.shutdown();
    const streams = try pair();
    var client_open = true;
    defer if (client_open) streams[0].close(io);
    defer streams[1].close(io);
    var server = try io.concurrent(connection.serve, .{ io, testing.allocator, streams[1], &peer, tasks, pids, 1, connection.Config{} });
    defer _ = server.cancel(io) catch {};
    var writer = streams[0].writer(io, &.{});
    var reader = streams[0].reader(io, &.{});
    try send(&writer.interface, pids[0], 11, "abc");
    try send(&writer.interface, pids[1], 12, "abc");
    var seen: [2]bool = @splat(false);
    for (0..2) |_| {
        var value = try read(&reader.interface);
        defer value.deinit(testing.allocator);
        const id = value.tuple[0].reference.ids[0];
        try testing.expect(id == 11 or id == 12);
        try testing.expect(!seen[id - 11]);
        seen[id - 11] = true;
        try testing.expectEqualStrings("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", &std.fmt.bytesToHex(value.tuple[1].tuple[1].binary[0..32].*, .lower));
    }
    streams[0].close(io);
    client_open = false;
    try expectDisconnect(server.await(io));
}

test "disconnect drains accepted old-epoch work before a new peer" {
    var control = @import("task_runtime_test.zig").Control{};
    const tasks = try Runtime.create(testing.allocator, io, .{ "a", "b" });
    defer tasks.deinit() catch unreachable;
    defer _ = tasks.shutdown();
    tasks.control = &control;
    const first = try pair();
    var first_open = true;
    defer if (first_open) first[0].close(io);
    defer first[1].close(io);
    var old = try io.concurrent(connection.serve, .{ io, testing.allocator, first[1], &peer, tasks, pids, 1, connection.Config{} });
    defer {
        control.release.set(io);
        _ = old.cancel(io) catch {};
    }
    var writer = first[0].writer(io, &.{});
    try send(&writer.interface, pids[0], 1, "old");
    try control.entered.waitTimeout(io, .{ .duration = .{ .raw = .fromSeconds(5), .clock = .awake } });
    first[0].close(io);
    first_open = false;
    control.release.set(io);
    try expectDisconnect(old.await(io));
    tasks.control = null;
    const second = try pair();
    var second_open = true;
    defer if (second_open) second[0].close(io);
    defer second[1].close(io);
    var fresh = try io.concurrent(connection.serve, .{ io, testing.allocator, second[1], &peer, tasks, pids, 2, connection.Config{} });
    defer _ = fresh.cancel(io) catch {};
    var next_writer = second[0].writer(io, &.{});
    var next_reader = second[0].reader(io, &.{});
    try send(&next_writer.interface, pids[1], 2, "abc");
    var value = try read(&next_reader.interface);
    defer value.deinit(testing.allocator);
    try testing.expectEqual(@as(u32, 2), value.tuple[0].reference.ids[0]);
    try testing.expectEqualStrings("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", &std.fmt.bytesToHex(value.tuple[1].tuple[1].binary[0..32].*, .lower));
    second[0].close(io);
    second_open = false;
    try expectDisconnect(fresh.await(io));
}
