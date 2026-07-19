const std = @import("std");
const transport = @import("zbeam-transport");

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
