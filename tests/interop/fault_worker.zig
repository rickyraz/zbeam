//! Test-only startup faults; no production wire command can select them.
const std = @import("std");
const z = @import("zbeam");
const Fault = enum { none, panic, oom, spin, pause, workers };

fn serve(io: std.Io, allocator: std.mem.Allocator, server: *std.Io.net.Server, config: z.runtime.node.Config, fault: Fault) !void {
    var worker = z.runtime.worker.Worker{ .pid = .{ .node = config.node_name, .creation = config.creation, .id = 1, .serial = 0 } };
    try worker.start();
    var used = false;
    while (true) {
        const stream = try server.accept(io);
        defer stream.close(io);
        var random: [4]u8 = undefined;
        io.random(&random);
        var peer = try z.transport.handshake_io.accept(stream, io, allocator, .{
            .node_name = config.node_name,
            .cookie = config.cookie,
            .creation = config.creation,
            .flags = config.flags,
            .challenge = @bitCast(random),
            .timeout = .fromSeconds(2),
        });
        defer peer.deinit(allocator);
        defer worker.clearMonitors();
        var reader = stream.reader(io, &.{});
        var writer = stream.writer(io, &.{});
        var demand = z.actor.Demand.init(1);
        while (true) {
            const bytes = try z.transport.distribution_io.readDemandedPacket(allocator, &reader.interface, z.runtime.worker.limits.max_packet_bytes, &demand);
            defer allocator.free(bytes);
            var packet = try z.protocol.distribution.decodePacket(allocator, bytes, z.runtime.worker.limits);
            defer packet.deinit(allocator);
            const work = packet == .message and packet.message.control == .tuple and packet.message.control.tuple.len > 0 and packet.message.control.tuple[0] == .integer and packet.message.control.tuple[0].integer == z.protocol.distribution.send;
            if (work and !used) {
                used = true;
                switch (fault) {
                    .none => {},
                    .panic => @panic("test-only worker panic"),
                    .oom => {
                        var failing = std.testing.FailingAllocator.init(allocator, .{ .fail_index = 0 });
                        try worker.handle(failing.allocator(), bytes, &peer, &writer.interface);
                        return error.ExpectedAllocationFailure;
                    },
                    .spin => while (true) std.atomic.spinLoopHint(),
                    .pause => try io.sleep(.fromSeconds(2), .awake),
                    .workers => unreachable,
                }
            }
            try worker.handle(allocator, bytes, &peer, &writer.interface);
            try demand.grant(1);
        }
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
    const config = z.runtime.node.Config{ .node_name = full, .cookie = cookie, .creation = registration.creation, .flags = z.protocol.flags.m1 | z.runtime.worker.monitor_flags, .service = if (fault == .workers) .workers else .echo, .max_connections = if (fault == .workers) 0 else 1 };
    const Result = union(enum) { service: anyerror!void, registration: anyerror!void };
    var storage: [2]Result = undefined;
    var tasks = std.Io.Select(Result).init(init.io, &storage);
    defer tasks.cancelDiscard();
    if (fault == .workers)
        try tasks.concurrent(.service, z.runtime.node.serve, .{ init.io, init.gpa, &server, config })
    else
        try tasks.concurrent(.service, serve, .{ init.io, init.gpa, &server, config, fault });
    try tasks.concurrent(.registration, z.transport.epmd_client.Registration.waitLost, .{ &registration, init.io });
    switch (try tasks.await()) {
        .service => |result| try result,
        .registration => |result| {
            try result;
            return error.EpmdRegistrationLost;
        },
    }
}
