const std = @import("std");
const etf = @import("zbeam-etf");
const protocol = @import("zbeam-protocol");
const transport = @import("zbeam-transport");
const runtime = @import("zbeam-runtime");

const PeerContext = struct {
    server: *std.Io.net.Server,
    failure: ?anyerror = null,
};

fn serveOneEcho(context: *PeerContext) std.Io.Cancelable!void {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const stream = context.server.accept(io) catch |err| switch (err) {
        error.Canceled => return error.Canceled,
        else => {
            context.failure = err;
            return;
        },
    };
    defer stream.close(io);
    var peer = transport.handshake_io.accept(stream, io, allocator, .{
        .node_name = "echo@127.0.0.1",
        .cookie = "cookie",
        .flags = 1,
        .creation = 2,
        .challenge = 200,
    }) catch |err| {
        context.failure = err;
        return;
    };
    defer peer.deinit(allocator);

    var read_buffer: [4096]u8 = undefined;
    var write_buffer: [4096]u8 = undefined;
    var stream_reader = stream.reader(io, &read_buffer);
    var stream_writer = stream.writer(io, &write_buffer);
    const incoming = transport.distribution_io.readPacket(allocator, &stream_reader.interface, 64 * 1024) catch |err| {
        context.failure = err;
        return;
    };
    defer allocator.free(incoming);
    const response = (runtime.Echo{ .registered_name = "echo" }).handle(allocator, incoming) catch |err| {
        context.failure = err;
        return;
    } orelse {
        context.failure = error.ActorNotFound;
        return;
    };
    defer allocator.free(response);
    transport.distribution_io.writePacket(&stream_writer.interface, response) catch |err| {
        context.failure = err;
    };
}

test "one registered echo actor replies through handshake and distribution framing" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var address: std.Io.net.IpAddress = .{ .ip4 = .loopback(0) };
    var server = try address.listen(io, .{ .reuse_address = true });
    defer server.deinit(io);

    var context = PeerContext{ .server = &server };
    var group: std.Io.Group = .init;
    defer group.cancel(io);
    try group.concurrent(io, serveOneEcho, .{&context});

    const stream = try server.socket.address.connect(io, .{ .mode = .stream });
    defer stream.close(io);
    var peer = try transport.handshake_io.initiate(stream, io, allocator, .{
        .node_name = "client@127.0.0.1",
        .cookie = "cookie",
        .flags = 1,
        .creation = 1,
        .challenge = 100,
    });
    defer peer.deinit(allocator);

    var control_items = [_]etf.Term{
        .{ .integer = protocol.distribution.reg_send },
        .{ .pid = .{ .node = "client@127.0.0.1", .id = 1, .serial = 0, .creation = 1 } },
        .{ .atom = "" },
        .{ .atom = "echo" },
    };
    var control = etf.Term{ .tuple = &control_items };
    var payload = etf.Term{ .atom = "hello" };
    const request = try protocol.distribution.encodePacket(allocator, &control, &payload);
    defer allocator.free(request);

    var read_buffer: [4096]u8 = undefined;
    var write_buffer: [4096]u8 = undefined;
    var stream_reader = stream.reader(io, &read_buffer);
    var stream_writer = stream.writer(io, &write_buffer);
    try transport.distribution_io.writePacket(&stream_writer.interface, request);
    const response = try transport.distribution_io.readPacket(allocator, &stream_reader.interface, 64 * 1024);
    defer allocator.free(response);
    var decoded = try protocol.distribution.decodePacket(allocator, response, .{});
    defer decoded.deinit(allocator);
    var decoded_payload = try decoded.message.decodePayload(allocator, .{});
    defer decoded_payload.deinit(allocator);
    try std.testing.expectEqualStrings("hello", decoded_payload.atom);

    try group.await(io);
    if (context.failure) |failure| return failure;
}
