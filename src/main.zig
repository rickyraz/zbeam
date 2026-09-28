const std = @import("std");
const zbeam = @import("zbeam");

pub fn main(init: std.process.Init) !void {
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();
    _ = args.next();
    const command = args.next() orelse return printStatus(init);
    const serving = std.mem.eql(u8, command, "serve");
    const probing = std.mem.eql(u8, command, "probe");
    if (!serving and !probing and !std.mem.eql(u8, command, "echo")) return error.UnknownCommand;
    const short_name = args.next() orelse return error.MissingNodeName;
    try validateName(short_name);
    const cookie = args.next() orelse return error.MissingCookie;
    if (cookie.len == 0) return error.EmptyCookie;
    const peer_name = if (probing) args.next() orelse return error.MissingPeerName else null;
    if (peer_name) |name| try validateName(name);
    const max_messages = if (!probing) blk: {
        break :blk if (args.next()) |value| try std.fmt.parseInt(usize, value, 10) else if (serving) @as(usize, 0) else @as(usize, 1);
    } else 1;
    if (args.next() != null) return error.UnexpectedArgument;
    try run(init, short_name, cookie, max_messages, serving, peer_name);
}

fn validateName(name: []const u8) !void {
    if (name.len == 0 or name.len > 245) return error.InvalidNodeName;
    for (name) |byte| {
        if (!std.ascii.isAlphanumeric(byte) and byte != '_' and byte != '-' and byte != '.') return error.InvalidNodeName;
    }
}

fn printStatus(init: std.process.Init) !void {
    var buffer: [1024]u8 = undefined;
    var writer: std.Io.File.Writer = .initStreaming(.stdout(), init.io, &buffer);
    try writer.interface.writeAll(
        \\zbeam single-actor MVP (restricted distribution subset)
        \\Usage: zbeam echo <short-name> <cookie> [message-count]
        \\       zbeam serve <short-name> <cookie> [messages-per-peer]
        \\       zbeam probe <short-name> <cookie> <peer-short-name>
        \\Loopback only; start epmd -daemon first.
        \\echo: one peer, one message by default; zero messages means until disconnect.
        \\serve: sequential peers until stopped; unlimited messages by default.
        \\probe: initiate a connection and verify one echo round trip with an OTP actor.
        \\
    );
    try writer.interface.flush();
}

fn run(init: std.process.Init, short_name: []const u8, cookie: []const u8, max_messages: usize, serving: bool, peer_name: ?[]const u8) !void {
    const allocator = init.gpa;
    const io = init.io;
    const full_name = try std.fmt.allocPrint(allocator, "{s}@127.0.0.1", .{short_name});
    defer allocator.free(full_name);
    const address: std.Io.net.IpAddress = .{ .ip4 = .loopback(0) };
    var server = try address.listen(io, .{ .reuse_address = true });
    defer server.deinit(io);
    const epmd = zbeam.transport.epmd_client.Client{ .io = io };
    var registration = try epmd.register(allocator, .{ .port = server.socket.address.getPort(), .node_name = short_name });
    defer registration.close(io);
    const config = zbeam.runtime.node.Config{
        .node_name = full_name,
        .cookie = cookie,
        .creation = registration.creation,
        .max_messages = max_messages,
        .max_connections = if (serving) 0 else 1,
    };
    var buffer: [1024]u8 = undefined;
    var writer: std.Io.File.Writer = .initStreaming(.stdout(), io, &buffer);
    if (peer_name) |name| {
        var info = try epmd.lookup(allocator, name, 1024);
        defer info.deinit(allocator);
        if (info.protocol != 0 or info.lowest > 6 or info.highest < 6 or !std.mem.eql(u8, info.node_name, name)) return error.UnsupportedPeer;
        const peer_address: std.Io.net.IpAddress = .{ .ip4 = .loopback(info.port) };
        const stream = try peer_address.connect(io, .{ .mode = .stream });
        defer stream.close(io);
        const expected = try std.fmt.allocPrint(allocator, "{s}@127.0.0.1", .{name});
        defer allocator.free(expected);
        try zbeam.runtime.node.probe(io, allocator, stream, config, expected);
        try writer.interface.print("probe PASS {s}\n", .{expected});
        try writer.interface.flush();
        return;
    }
    try writer.interface.print("registered {s} on port {d}; waiting for peer\n", .{ full_name, server.socket.address.getPort() });
    try writer.interface.flush();
    try serveRegistered(io, allocator, &server, &registration, config);
}

/// Fail closed if EPMD loses the registration, rather than serving an
/// undiscoverable node. Cancellation joins the active socket task first.
fn serveRegistered(io: std.Io, allocator: std.mem.Allocator, server: *std.Io.net.Server, registration: *zbeam.transport.epmd_client.Registration, config: zbeam.runtime.node.Config) !void {
    const U = union(enum) { service: anyerror!void, registration: anyerror!void };
    var storage: [2]U = undefined;
    var select = std.Io.Select(U).init(io, &storage);
    try select.concurrent(.service, zbeam.runtime.node.serve, .{ io, allocator, server, config });
    defer select.cancelDiscard();
    try select.concurrent(.registration, zbeam.transport.epmd_client.Registration.waitLost, .{ registration, io });
    switch (try select.await()) {
        .service => |result| try result,
        .registration => |result| {
            try result;
            return error.EpmdRegistrationLost;
        },
    }
}

test "closed registration cancels listening service" {
    const io = std.testing.io;
    const address: std.Io.net.IpAddress = .{ .ip4 = .loopback(0) };
    var epmd_server = try address.listen(io, .{ .reuse_address = true });
    defer epmd_server.deinit(io);
    const stream = try epmd_server.socket.address.connect(io, .{ .mode = .stream });
    var registration: zbeam.transport.epmd_client.Registration = .{ .stream = stream, .creation = 1 };
    defer registration.close(io);
    const epmd_side = try epmd_server.accept(io);
    var worker_server = try address.listen(io, .{ .reuse_address = true });
    defer worker_server.deinit(io);
    epmd_side.close(io);
    try std.testing.expectError(error.EpmdRegistrationLost, serveRegistered(io, std.testing.allocator, &worker_server, &registration, .{
        .node_name = "worker@127.0.0.1",
        .cookie = "cookie",
        .creation = 1,
        .max_connections = 0,
    }));
}

test "CLI restricts node names to safe short loopback identities" {
    try validateName("worker-1.test");
    try std.testing.expectError(error.InvalidNodeName, validateName(""));
    try std.testing.expectError(error.InvalidNodeName, validateName("node@host"));
    try std.testing.expectError(error.InvalidNodeName, validateName("node\n"));
}
