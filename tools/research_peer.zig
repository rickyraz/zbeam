//! Test-only peer; fault selection is a startup argument, never a wire operation.
const std = @import("std");
const z = @import("zbeam");
const Fault = enum { none, oom, panic, spin };
const Handler = struct {
    io: std.Io,
    pause_ms: u32,
    fault: Fault,
    used: bool = false,
    pub fn handle(self: *@This(), a: std.mem.Allocator, bytes: []const u8) !?[]u8 {
        var packet = try z.protocol.distribution.decodePacket(a, bytes, .{});
        defer packet.deinit(a);
        if (packet == .message) {
            const route = try z.protocol.distribution.regSendDestination(&packet.message.control);
            if (!self.used and std.mem.eql(u8, route.name, "sha256")) {
                self.used = true;
                try announce(self.io, "PAUSED\n");
                try self.io.sleep(.fromMilliseconds(self.pause_ms), .awake);
                switch (self.fault) {
                    .none => {},
                    .oom => {
                        var failing = std.testing.FailingAllocator.init(a, .{ .fail_index = 0 });
                        return (z.runtime.Sha256{}).handle(failing.allocator(), bytes);
                    },
                    .panic => @panic("test-only worker panic"),
                    .spin => while (true) std.atomic.spinLoopHint(),
                }
                try announce(self.io, "RESUMED\n");
            }
        }
        return (z.runtime.Sha256{}).handle(a, bytes);
    }
};
fn announce(io: std.Io, text: []const u8) !void {
    var buffer: [128]u8 = undefined;
    var out = std.Io.File.Writer.initStreaming(.stdout(), io, &buffer);
    try out.interface.writeAll(text);
    try out.interface.flush();
}
fn connection(io: std.Io, a: std.mem.Allocator, stream: std.Io.net.Stream, config: z.runtime.node.Config, handler: *Handler) !void {
    var random: [4]u8 = undefined;
    io.random(&random);
    var peer = try z.transport.handshake_io.accept(stream, io, a, .{
        .node_name = config.node_name,
        .cookie = config.cookie,
        .creation = config.creation,
        .challenge = @bitCast(random),
        .flags = config.flags,
        .timeout = config.handshake_timeout,
    });
    defer peer.deinit(a);
    try z.runtime.node.dispatch(io, a, stream, config, handler);
}
fn serve(io: std.Io, a: std.mem.Allocator, server: *std.Io.net.Server, config: z.runtime.node.Config, handler: *Handler) !void {
    while (true) {
        const stream = try server.accept(io);
        defer stream.close(io);
        connection(io, a, stream, config, handler) catch |err| {
            if (err == error.Canceled or err == error.OutOfMemory) return err;
        };
    }
}
pub fn main(init: std.process.Init) !void {
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();
    _ = args.next();
    const name = args.next() orelse return error.MissingName;
    if (name.len == 0 or name.len > 240) return error.InvalidName;
    for (name) |byte| if (!std.ascii.isAlphanumeric(byte) and byte != '_') return error.InvalidName;
    const cookie = args.next() orelse return error.MissingCookie;
    if (cookie.len == 0) return error.EmptyCookie;
    const pause = try std.fmt.parseInt(u32, args.next() orelse return error.MissingPause, 10);
    if (pause > 30000) return error.InvalidPause;
    const fault = std.meta.stringToEnum(Fault, args.next() orelse "none") orelse return error.InvalidFault;
    const epmd_port = try std.fmt.parseInt(u16, args.next() orelse "4369", 10);
    if (args.next() != null) return error.UnexpectedArgument;
    const full = try std.fmt.allocPrint(init.gpa, "{s}@127.0.0.1", .{name});
    defer init.gpa.free(full);
    var server = try (std.Io.net.IpAddress{ .ip4 = .loopback(0) }).listen(init.io, .{ .reuse_address = true });
    defer server.deinit(init.io);
    const epmd = z.transport.epmd_client.Client{ .io = init.io, .address = .{ .ip4 = .loopback(epmd_port) } };
    var registration = try epmd.register(init.gpa, .{ .port = server.socket.address.getPort(), .node_name = name });
    defer registration.close(init.io);
    var handler = Handler{ .io = init.io, .pause_ms = pause, .fault = fault };
    const config = z.runtime.node.Config{ .node_name = full, .cookie = cookie, .creation = registration.creation, .max_messages = 0, .max_connections = 0, .limits = .{ .max_packet_bytes = 2 * 1024 * 1024, .etf = .{ .max_binary_bytes = 1024 * 1024, .max_allocated_bytes = 4 * 1024 * 1024 } } };
    const U = union(enum) { service: anyerror!void, registration: anyerror!void };
    var storage: [2]U = undefined;
    var select = std.Io.Select(U).init(init.io, &storage);
    try select.concurrent(.service, serve, .{ init.io, init.gpa, &server, config, &handler });
    defer select.cancelDiscard();
    try select.concurrent(.registration, z.transport.epmd_client.Registration.waitLost, .{ &registration, init.io });
    try announce(init.io, "READY\n");
    switch (try select.await()) {
        .service => |result| try result,
        .registration => |result| {
            try result;
            return error.EpmdRegistrationLost;
        },
    }
}
