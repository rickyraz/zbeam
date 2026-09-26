const std = @import("std");
const etf = @import("zbeam-etf");
const protocol = @import("zbeam-protocol");
const transport = @import("zbeam-transport");
const actor = @import("zbeam-actor");
const runtime = @import("zbeam-runtime");

const PeerContext = struct {
    server: *std.Io.net.Server,
    failure: ?anyerror = null,

    fn run(self: *PeerContext) void {
        runtime.node.serve(std.testing.io, std.testing.allocator, self.server, .{
            .node_name = "echo@127.0.0.1",
            .cookie = "cookie",
            .creation = 2,
            .max_messages = 1,
            .max_connections = 5,
            .limits = .{ .max_packet_bytes = 1024 },
        }) catch |err| {
            self.failure = err;
        };
    }
};

test "runtime rejects bad peers and handles ticks, dropped routes and reconnects" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const address: std.Io.net.IpAddress = .{ .ip4 = .loopback(0) };
    var server = try address.listen(io, .{ .reuse_address = true });
    defer server.deinit(io);
    var context = PeerContext{ .server = &server };
    var group: std.Io.Group = .init;
    defer group.cancel(io);
    try group.concurrent(io, PeerContext.run, .{&context});

    for (0..5) |attempt| {
        const stream = try server.socket.address.connect(io, .{ .mode = .stream });
        defer stream.close(io);
        const config = transport.handshake_io.Config{
            .node_name = "client@127.0.0.1",
            .cookie = if (attempt == 0) "wrong" else "cookie",
            .flags = protocol.flags.m1,
            .creation = 1,
            .challenge = 100,
        };
        if (attempt == 0) {
            try std.testing.expectError(error.EndOfStream, transport.handshake_io.initiate(stream, io, allocator, config));
            continue;
        }
        var peer = try transport.handshake_io.initiate(stream, io, allocator, config);
        defer peer.deinit(allocator);
        if (attempt == 4) continue; // Clean EOF at a frame boundary.
        var reader = stream.reader(io, &.{});
        var writer = stream.writer(io, &.{});
        if (attempt == 1) {
            try writer.interface.writeAll(&.{ 0, 0, 4, 1 }); // 1025 > configured bound
            var byte: [1]u8 = undefined;
            try std.testing.expectError(error.EndOfStream, reader.interface.readSliceAll(&byte));
            continue;
        }
        try transport.distribution_io.writePacket(&writer.interface, &protocol.distribution.tickPacket());
        const tick = try transport.distribution_io.readPacket(allocator, &reader.interface, 1024);
        defer allocator.free(tick);
        try std.testing.expectEqualSlices(u8, &protocol.distribution.tickPacket(), tick);

        var control_items = [_]etf.Term{
            .{ .integer = protocol.distribution.reg_send },
            .{ .pid = .{ .node = "client@127.0.0.1", .id = 1, .serial = 0, .creation = 1 } },
            .{ .atom = "" },
            .{ .atom = "absent" },
        };
        var control = etf.Term{ .tuple = &control_items };
        var payload = etf.Term{ .integer = @intCast(attempt) };
        const dropped = try protocol.distribution.encodePacket(allocator, &control, &payload);
        defer allocator.free(dropped);
        try transport.distribution_io.writePacket(&writer.interface, dropped);
        control_items[3] = .{ .atom = "echo" };
        const request = try protocol.distribution.encodePacket(allocator, &control, &payload);
        defer allocator.free(request);
        try transport.distribution_io.writePacket(&writer.interface, request);
        const response = try transport.distribution_io.readPacket(allocator, &reader.interface, 1024);
        defer allocator.free(response);
        var decoded = try protocol.distribution.decodePacket(allocator, response, .{});
        defer decoded.deinit(allocator);
        var result = try decoded.message.decodePayload(allocator, .{});
        defer result.deinit(allocator);
        try std.testing.expectEqual(@as(i64, @intCast(attempt)), result.integer);
    }
    try group.await(io);
    if (context.failure) |err| return err;
}

const ProbePeer = struct {
    server: *std.Io.net.Server,
    failure: ?anyerror = null,

    fn run(self: *ProbePeer) void {
        self.serve() catch |err| {
            self.failure = err;
        };
    }

    fn serve(self: *ProbePeer) !void {
        const io = std.testing.io;
        const allocator = std.testing.allocator;
        const stream = try self.server.accept(io);
        defer stream.close(io);
        var peer = try transport.handshake_io.accept(stream, io, allocator, .{
            .node_name = "otp@host",
            .cookie = "cookie",
            .flags = protocol.flags.m1,
            .creation = 1,
            .challenge = 321,
        });
        defer peer.deinit(allocator);
        var fields = [_]etf.Term{
            .{ .integer = protocol.distribution.reg_send },
            .{ .pid = .{ .node = "otp@host", .id = 1, .serial = 0, .creation = 1 } },
            .{ .atom = "" },
            .{ .atom = "global_name_server" },
        };
        var control = etf.Term{ .tuple = &fields };
        const housekeeping = try protocol.distribution.encodePacket(allocator, &control, null);
        defer allocator.free(housekeeping);
        var writer = stream.writer(io, &.{});
        try transport.distribution_io.writePacket(&writer.interface, housekeeping);
        try transport.distribution_io.writePacket(&writer.interface, &protocol.distribution.tickPacket());
        var reader = stream.reader(io, &.{});
        const request = try transport.distribution_io.readPacket(allocator, &reader.interface, 4096);
        defer allocator.free(request);
        const tick = try transport.distribution_io.readPacket(allocator, &reader.interface, 4096);
        defer allocator.free(tick);
        try std.testing.expectEqualSlices(u8, &protocol.distribution.tickPacket(), tick);
        const response = (try (runtime.Echo{ .registered_name = "echo" }).handle(allocator, request)).?;
        defer allocator.free(response);
        try transport.distribution_io.writePacket(&writer.interface, response);
    }
};

test "initiating probe skips unrelated registered messages and ticks before SEND" {
    const io = std.testing.io;
    const address: std.Io.net.IpAddress = .{ .ip4 = .loopback(0) };
    var server = try address.listen(io, .{ .reuse_address = true });
    defer server.deinit(io);
    var peer = ProbePeer{ .server = &server };
    var group: std.Io.Group = .init;
    defer group.cancel(io);
    try group.concurrent(io, ProbePeer.run, .{&peer});
    const stream = try server.socket.address.connect(io, .{ .mode = .stream });
    defer stream.close(io);
    try runtime.node.probe(io, std.testing.allocator, stream, .{ .node_name = "probe@host", .cookie = "cookie", .creation = 1 }, "otp@host");
    try group.await(io);
    if (peer.failure) |err| return err;
}

const CountedReader = struct {
    interface: std.Io.Reader = .{ .vtable = &.{ .stream = stream }, .buffer = &.{}, .seek = 0, .end = 0 },
    bytes: []const u8,
    read_calls: usize = 0,

    fn stream(reader: *std.Io.Reader, writer: *std.Io.Writer, limit: std.Io.Limit) std.Io.Reader.StreamError!usize {
        const self: *CountedReader = @fieldParentPtr("interface", reader);
        self.read_calls += 1;
        if (self.bytes.len == 0) return error.EndOfStream;
        const bytes = self.bytes[0..limit.minInt(self.bytes.len)];
        const n = try writer.write(bytes);
        self.bytes = self.bytes[n..];
        return n;
    }
};

test "zero demand performs no read or allocation and one grant reads exactly one frame" {
    var source = CountedReader{ .bytes = &.{ 0, 0, 0, 1, 112, 0, 0, 0, 0 } };
    var demand = actor.Demand.init(0);
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectError(error.NoDemand, transport.distribution_io.readDemandedPacket(failing.allocator(), &source.interface, 1024, &demand));
    try std.testing.expectEqual(@as(usize, 0), source.read_calls);
    try demand.grant(1);
    const frame = try transport.distribution_io.readDemandedPacket(std.testing.allocator, &source.interface, 1024, &demand);
    defer std.testing.allocator.free(frame);
    try std.testing.expectEqual(@as(usize, 5), frame.len);
    try std.testing.expectEqual(@as(usize, 4), source.bytes.len);
    const calls = source.read_calls;
    try std.testing.expectError(error.NoDemand, transport.distribution_io.readDemandedPacket(failing.allocator(), &source.interface, 1024, &demand));
    try std.testing.expectEqual(calls, source.read_calls);
    var buffered = std.Io.Reader.fixed(source.bytes);
    try demand.grant(1);
    try std.testing.expectError(error.BufferedReader, transport.distribution_io.readDemandedPacket(std.testing.allocator, &buffered, 1024, &demand));
    try std.testing.expectEqual(@as(u32, 1), demand.load());
}
