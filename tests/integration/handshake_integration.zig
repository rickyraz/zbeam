const std = @import("std");
const transport = @import("zbeam-transport");
const handshake = @import("zbeam-protocol").handshake;

const AcceptContext = struct {
    server: *std.Io.net.Server,
    peer: ?transport.handshake_io.Peer = null,
    failure: ?anyerror = null,
};

fn acceptPeer(context: *AcceptContext) std.Io.Cancelable!void {
    const io = std.testing.io;
    const stream = context.server.accept(io) catch |err| switch (err) {
        error.Canceled => return error.Canceled,
        else => {
            context.failure = err;
            return;
        },
    };
    defer stream.close(io);
    context.peer = transport.handshake_io.accept(stream, io, std.testing.allocator, .{
        .node_name = "acceptor@127.0.0.1",
        .cookie = "cookie",
        .flags = 1,
        .creation = 2,
        .challenge = 200,
    }) catch |err| {
        context.failure = err;
        return;
    };
}

// Deliberately coalesces the last handshake frame and first distribution frame.
const Pipeline = struct {
    server: *std.Io.net.Server,
    initiator: bool,
    failure: ?anyerror = null,

    fn run(self: *Pipeline) void {
        self.exchange() catch |err| {
            self.failure = err;
        };
    }

    fn read(reader: *std.Io.Reader) ![]u8 {
        var header: [2]u8 = undefined;
        try reader.readSliceAll(&header);
        const bytes = try std.testing.allocator.alloc(u8, std.mem.readInt(u16, &header, .big));
        errdefer std.testing.allocator.free(bytes);
        try reader.readSliceAll(bytes);
        return bytes;
    }

    fn exchange(self: *Pipeline) !void {
        const allocator = std.testing.allocator;
        const io = std.testing.io;
        const stream = try self.server.accept(io);
        defer stream.close(io);
        var reader = stream.reader(io, &.{});
        var buffer: [4096]u8 = undefined;
        var writer = stream.writer(io, &buffer);
        if (self.initiator) {
            const name = try handshake.encodeName(allocator, .{ .flags = 1, .creation = 1, .node_name = "manual@host" });
            defer allocator.free(name);
            try writer.interface.writeAll(name);
            try writer.interface.flush();
            const status = try read(&reader.interface);
            defer allocator.free(status);
            const challenge_bytes = try read(&reader.interface);
            defer allocator.free(challenge_bytes);
            var challenge = try handshake.decodeChallenge(allocator, challenge_bytes);
            defer challenge.deinit(allocator);
            const reply = try handshake.encodeReply(allocator, .{ .challenge = 123, .digest = handshake.cookieDigest("cookie", challenge.challenge) });
            defer allocator.free(reply);
            try writer.interface.writeAll(reply);
            try writer.interface.writeAll(&.{ 0, 0, 0, 0 });
            try writer.interface.flush();
            const ack = try read(&reader.interface);
            defer allocator.free(ack);
        } else {
            const name = try read(&reader.interface);
            defer allocator.free(name);
            const status = try handshake.encodeStatus(allocator, .ok);
            defer allocator.free(status);
            const challenge = try handshake.encodeChallenge(allocator, .{ .flags = 1, .creation = 1, .node_name = "manual@host", .challenge = 123 });
            defer allocator.free(challenge);
            try writer.interface.writeAll(status);
            try writer.interface.writeAll(challenge);
            try writer.interface.flush();
            const reply_bytes = try read(&reader.interface);
            defer allocator.free(reply_bytes);
            const reply = try handshake.decodeReply(reply_bytes);
            const ack = try handshake.encodeAck(allocator, .{ .digest = handshake.cookieDigest("cookie", reply.challenge) });
            defer allocator.free(ack);
            try writer.interface.writeAll(ack);
            try writer.interface.writeAll(&.{ 0, 0, 0, 0 });
            try writer.interface.flush();
        }
    }
};

test "handshake handoff preserves coalesced distribution bytes in both roles" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    for ([_]bool{ false, true }) |initiator| {
        const address: std.Io.net.IpAddress = .{ .ip4 = .loopback(0) };
        var server = try address.listen(io, .{ .reuse_address = true });
        defer server.deinit(io);
        var pipeline = Pipeline{ .server = &server, .initiator = initiator };
        var group: std.Io.Group = .init;
        defer group.cancel(io);
        try group.concurrent(io, Pipeline.run, .{&pipeline});
        const stream = try server.socket.address.connect(io, .{ .mode = .stream });
        defer stream.close(io);
        const config = transport.handshake_io.Config{ .node_name = "zbeam@host", .cookie = "cookie", .flags = 1, .creation = 1, .challenge = 321 };
        var peer = if (initiator)
            try transport.handshake_io.accept(stream, io, allocator, config)
        else
            try transport.handshake_io.initiate(stream, io, allocator, config);
        defer peer.deinit(allocator);
        var reader = stream.reader(io, &.{});
        var tick: [4]u8 = undefined;
        try reader.interface.readSliceAll(&tick);
        try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0, 0 }, &tick);
        try group.await(io);
        if (pipeline.failure) |err| return err;
    }
}

const TimedAcceptor = struct {
    server: *std.Io.net.Server,
    outcomes: [3]?anyerror = .{ null, null, null },

    fn run(self: *@This()) void {
        const io = std.testing.io;
        for (0..3) |index| {
            const stream = self.server.accept(io) catch |err| {
                self.outcomes[index] = err;
                return;
            };
            defer stream.close(io);
            var peer = transport.handshake_io.accept(stream, io, std.testing.allocator, .{
                .node_name = "acceptor@127.0.0.1",
                .cookie = "cookie",
                .flags = 1,
                .creation = 2,
                .challenge = 200,
                .timeout = .fromMilliseconds(120),
            }) catch |err| {
                self.outcomes[index] = err;
                continue;
            };
            peer.deinit(std.testing.allocator);
        }
    }
};

test "partial NAME and REPLY expire without consuming the next peer" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const address: std.Io.net.IpAddress = .{ .ip4 = .loopback(0) };
    var server = try address.listen(io, .{ .reuse_address = true });
    defer server.deinit(io);
    var context = TimedAcceptor{ .server = &server };
    var group: std.Io.Group = .init;
    defer group.cancel(io);
    try group.concurrent(io, TimedAcceptor.run, .{&context});
    for (0..3) |attempt| {
        const stream = try server.socket.address.connect(io, .{ .mode = .stream });
        defer stream.close(io);
        if (attempt == 2) {
            var peer = try transport.handshake_io.initiate(stream, io, allocator, .{
                .node_name = "client@127.0.0.1",
                .cookie = "cookie",
                .flags = 1,
                .creation = 1,
                .challenge = 100,
                .timeout = .fromSeconds(2),
            });
            peer.deinit(allocator);
            continue;
        }
        var writer = stream.writer(io, &.{});
        if (attempt == 0) {
            try writer.interface.writeAll(&.{0}); // partial NAME length
        } else {
            const name = try handshake.encodeName(allocator, .{ .flags = 1, .creation = 1, .node_name = "client@127.0.0.1" });
            defer allocator.free(name);
            try writer.interface.writeAll(name);
            var reader = stream.reader(io, &.{});
            const status = try Pipeline.read(&reader.interface);
            defer allocator.free(status);
            const challenge = try Pipeline.read(&reader.interface);
            defer allocator.free(challenge);
            try writer.interface.writeAll(&.{ 0, 21, 114 }); // partial REPLY
        }
        var byte: [1]u8 = undefined;
        var reader = stream.reader(io, &.{});
        try std.testing.expectError(error.EndOfStream, reader.interface.readSliceAll(&byte));
    }
    try group.await(io);
    try std.testing.expectEqual(error.Timeout, context.outcomes[0].?);
    try std.testing.expectEqual(error.Timeout, context.outcomes[1].?);
    try std.testing.expectEqual(@as(?anyerror, null), context.outcomes[2]);
}

test "initiating handshake expires when status never arrives" {
    const io = std.testing.io;
    const address: std.Io.net.IpAddress = .{ .ip4 = .loopback(0) };
    var server = try address.listen(io, .{ .reuse_address = true });
    defer server.deinit(io);
    const stream = try server.socket.address.connect(io, .{ .mode = .stream });
    defer stream.close(io);
    const stalled = try server.accept(io);
    defer stalled.close(io);
    try std.testing.expectError(error.Timeout, transport.handshake_io.initiate(stream, io, std.testing.allocator, .{
        .node_name = "client@127.0.0.1",
        .cookie = "cookie",
        .flags = 1,
        .creation = 1,
        .challenge = 100,
        .timeout = .fromMilliseconds(40),
    }));
}

test "initiating and accepting handshake roles interoperate over TCP" {
    const io = std.testing.io;
    var address: std.Io.net.IpAddress = .{ .ip4 = .loopback(0) };
    var server = try address.listen(io, .{ .reuse_address = true });
    defer server.deinit(io);

    var context = AcceptContext{ .server = &server };
    var group: std.Io.Group = .init;
    defer group.cancel(io);
    try group.concurrent(io, acceptPeer, .{&context});

    const stream = try server.socket.address.connect(io, .{ .mode = .stream });
    defer stream.close(io);
    var peer = try transport.handshake_io.initiate(stream, io, std.testing.allocator, .{
        .node_name = "initiator@127.0.0.1",
        .cookie = "cookie",
        .flags = 1,
        .creation = 1,
        .challenge = 100,
    });
    defer peer.deinit(std.testing.allocator);
    try group.await(io);

    if (context.failure) |failure| return failure;
    var accepted = context.peer orelse return error.MissingAcceptedPeer;
    defer accepted.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("acceptor@127.0.0.1", peer.node_name);
    try std.testing.expectEqualStrings("initiator@127.0.0.1", accepted.node_name);
}
