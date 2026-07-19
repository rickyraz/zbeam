const std = @import("std");
const zbeam = @import("zbeam");

pub fn main(init: std.process.Init) !void {
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();
    _ = args.next();
    const command = args.next() orelse return printStatus(init);

    if (std.mem.eql(u8, command, "echo")) {
        const short_name = args.next() orelse return error.MissingNodeName;
        const cookie = args.next() orelse return error.MissingCookie;
        if (args.next() != null) return error.UnexpectedArgument;
        return runEcho(init, short_name, cookie);
    }
    return error.UnknownCommand;
}

fn printStatus(init: std.process.Init) !void {
    var buffer: [1024]u8 = undefined;
    var file_writer: std.Io.File.Writer = .init(.stdout(), init.io, &buffer);
    const writer = &file_writer.interface;
    try writer.writeAll(
        \\zbeam pre-alpha
        \\Usage: zbeam echo <short-node-name> <cookie>
        \\The echo command accepts one peer and serves one registered `echo` message.
        \\
    );
    try writer.flush();
}

fn runEcho(init: std.process.Init, short_name: []const u8, cookie: []const u8) !void {
    const allocator = init.gpa;
    const io = init.io;
    const full_name = try std.fmt.allocPrint(allocator, "{s}@127.0.0.1", .{short_name});
    defer allocator.free(full_name);

    var address: std.Io.net.IpAddress = .{ .ip4 = .loopback(0) };
    var server = try address.listen(io, .{ .reuse_address = true });
    defer server.deinit(io);

    const epmd_client = zbeam.transport.epmd_client.Client{ .io = io };
    var registration = try epmd_client.register(allocator, .{
        .port = server.socket.address.getPort(),
        .node_name = short_name,
    });
    defer registration.close(io);

    var challenge_bytes: [4]u8 = undefined;
    io.random(&challenge_bytes);
    const challenge: u32 = @bitCast(challenge_bytes);

    var stdout_buffer: [1024]u8 = undefined;
    var file_writer: std.Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    try file_writer.interface.print("registered {s} on port {d}; waiting for one peer\n", .{ full_name, server.socket.address.getPort() });
    try file_writer.interface.flush();

    try zbeam.runtime.node.serveOne(io, allocator, &server, .{
        .node_name = full_name,
        .cookie = cookie,
        .creation = registration.creation,
        .challenge = challenge,
    });
}
