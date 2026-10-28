const std = @import("std");
const actor = @import("zbeam-actor");
const etf = @import("zbeam-etf");
const protocol = @import("zbeam-protocol");
const transport = @import("zbeam-transport");
const Echo = @import("echo.zig").Echo;
const Sha256 = @import("sha256.zig").Sha256;
const worker_service = @import("worker.zig");
const wire_service = @import("wire_service.zig");

pub const Config = struct {
    node_name: []const u8,
    cookie: []const u8,
    creation: u32,
    /// Deterministic override for tests only. Otherwise fresh per connection.
    challenge: ?u32 = null,
    registered_name: []const u8 = "echo",
    service: enum { echo, sha256, worker, workers } = .echo,
    flags: u64 = protocol.flags.m1,
    limits: protocol.distribution.Limits = .{},
    max_messages: usize = 1,
    /// One preserves the one-shot API; zero serves sequential peers until canceled.
    max_connections: usize = 1,
    /// One total budget per handshake; null is an explicit unbounded override.
    handshake_timeout: ?std.Io.Duration = .fromSeconds(5),
    /// Idle or incomplete frame; permit ordinary OTP tick intervals.
    frame_timeout: ?std.Io.Duration = .fromSeconds(90),
    /// Limits blocked replies without preempting CPU-bound handlers.
    write_timeout: ?std.Io.Duration = .fromSeconds(5),
};

/// One synchronous actor, one active peer, no prefetch and no detached tasks.
/// A connection owns its demand, reader and packet lifetimes. Reconnect starts
/// empty; the EPMD registration (and therefore creation) belongs to the caller.
pub fn serve(io: std.Io, allocator: std.mem.Allocator, server: *std.Io.net.Server, config: Config) !void {
    var workers: ?wire_service.Service = null;
    if (config.service == .workers) workers = try wire_service.Service.init(io, allocator, .{
        .node_name = config.node_name,
        .cookie = config.cookie,
        .creation = config.creation,
        .handshake_timeout = config.handshake_timeout,
        .connection = .{ .frame_timeout = config.frame_timeout, .write_timeout = config.write_timeout },
    });
    defer if (workers) |*state| state.deinit();
    var worker: ?worker_service.Worker = null;
    if (config.service == .worker) {
        var identity: [8]u8 = undefined;
        io.random(&identity);
        worker = .{ .pid = .{ .node = config.node_name, .creation = config.creation, .id = @bitCast(identity[0..4].*), .serial = @bitCast(identity[4..8].*) } };
        try worker.?.start();
    }
    var accepted: usize = 0;
    while (config.max_connections == 0 or accepted < config.max_connections) {
        const stream = try server.accept(io);
        defer stream.close(io);
        if (config.max_connections != 0) accepted += 1;
        (if (workers) |*state|
            state.servePeer(stream)
        else if (worker) |*state|
            serveWorkerConnection(io, allocator, stream, config, state)
        else
            serveConnection(io, allocator, stream, config)) catch |err| {
            // Recover only at the connection boundary; resource exhaustion and
            // cancellation remain visible to the caller/supervisor.
            if (err == error.EndOfStream) continue;
            if (fatalConnectionError(err, config)) return err;
            if (err != error.ConnectionResetByPeer)
                std.log.warn("peer disconnected: {s}", .{@errorName(err)});
        };
    }
}

fn fatalConnectionError(err: anyerror, config: Config) bool {
    if (err == error.Canceled or err == error.OutOfMemory or config.max_connections == 1) return true;
    return config.service == .workers and (err == error.ConcurrencyUnavailable or err == error.EpochExhausted or
        err == error.RequestIdExhausted or err == error.UnknownCompletion or err == error.MissingCompletion or
        err == error.NoProgress or err == error.ReservationOutstanding);
}

test "two-worker internal failures stop service without changing M1 error policy" {
    const base = Config{ .node_name = "node@host", .cookie = "cookie", .creation = 1, .max_connections = 0 };
    var m1 = base;
    m1.service = .worker;
    var m2 = base;
    m2.service = .workers;
    for ([_]anyerror{ error.ConcurrencyUnavailable, error.EpochExhausted, error.RequestIdExhausted, error.UnknownCompletion, error.MissingCompletion, error.NoProgress, error.ReservationOutstanding }) |err| {
        try std.testing.expect(!fatalConnectionError(err, m1));
        try std.testing.expect(fatalConnectionError(err, m2));
    }
    for ([_]anyerror{ error.Canceled, error.OutOfMemory }) |err| {
        try std.testing.expect(fatalConnectionError(err, m1) and fatalConnectionError(err, m2));
    }
    try std.testing.expect(!fatalConnectionError(error.InvalidControl, m1));
    try std.testing.expect(!fatalConnectionError(error.InvalidControl, m2));
    m1.max_connections = 1;
    try std.testing.expect(fatalConnectionError(error.InvalidControl, m1));
}

/// Initiating-role smoke request to an OTP actor implementing {From, Value}.
/// Verifies the authenticated identity, reply destination and exact payload.
pub fn probe(io: std.Io, allocator: std.mem.Allocator, stream: std.Io.net.Stream, config: Config, expected_peer: []const u8) !void {
    var random: [4]u8 = undefined;
    io.random(&random);
    var peer = try transport.handshake_io.initiate(stream, io, allocator, .{
        .node_name = config.node_name,
        .cookie = config.cookie,
        .creation = config.creation,
        .flags = config.flags,
        .challenge = config.challenge orelse @bitCast(random),
        .timeout = config.handshake_timeout,
    });
    defer peer.deinit(allocator);
    if (!std.mem.eql(u8, peer.node_name, expected_peer)) return error.UnexpectedPeer;
    const pid = etf.Pid{ .node = config.node_name, .id = 1, .serial = 0, .creation = config.creation };
    var control_items = [_]etf.Term{ .{ .integer = protocol.distribution.reg_send }, .{ .pid = pid }, .{ .atom = "" }, .{ .atom = config.registered_name } };
    var control = etf.Term{ .tuple = &control_items };
    var items = [_]etf.Term{ .{ .pid = pid }, .{ .atom = "hello" } };
    var payload = etf.Term{ .tuple = &items };
    const request = try protocol.distribution.encodePacket(allocator, &control, &payload);
    defer allocator.free(request);
    var writer = stream.writer(io, &.{});
    try transport.deadline.run(io, allocator, config.write_timeout, transport.distribution_io.writePacket, .{ &writer.interface, request }, transport.deadline.dropVoid);
    var reader = stream.reader(io, &.{});
    var demand = actor.Demand.init(1);
    while (true) {
        const bytes = transport.deadline.run(io, allocator, config.frame_timeout, transport.distribution_io.readDemandedPacket, .{ allocator, &reader.interface, config.limits.max_packet_bytes, &demand }, dropPacket) catch |err| return actualIoError(err, reader.err);
        defer allocator.free(bytes);
        var packet = try protocol.distribution.decodePacket(allocator, bytes, config.limits);
        defer packet.deinit(allocator);
        if (packet == .tick) {
            try transport.deadline.run(io, allocator, config.write_timeout, transport.distribution_io.writePacket, .{ &writer.interface, bytes }, transport.deadline.dropVoid);
            try demand.grant(1);
            continue;
        }
        const received = &packet.message.control;
        // Published OTP peers can send registered-name housekeeping before
        // the reply. This probe owns only its PID, not those registered names.
        if (received.* == .tuple and received.tuple.len > 0 and received.tuple[0] == .integer and received.tuple[0].integer == protocol.distribution.reg_send) {
            _ = try protocol.distribution.regSendDestination(received);
            try demand.grant(1);
            continue;
        }
        if (received.* != .tuple or received.tuple.len != 3) return error.InvalidControl;
        const fields = received.tuple;
        if (fields[0] != .integer or fields[0].integer != protocol.distribution.send or fields[2] != .pid) return error.InvalidControl;
        const to = fields[2].pid;
        if (!std.mem.eql(u8, to.node, pid.node) or to.id != pid.id or to.serial != pid.serial or to.creation != pid.creation) return error.UnexpectedRecipient;
        var reply = try packet.message.decodePayload(allocator, config.limits.etf);
        defer reply.deinit(allocator);
        const actual = try etf.encode(allocator, &reply);
        defer allocator.free(actual);
        const expected = try etf.encode(allocator, &payload);
        defer allocator.free(expected);
        if (!std.mem.eql(u8, actual, expected)) return error.UnexpectedReply;
        return;
    }
}

pub fn serveConnection(io: std.Io, allocator: std.mem.Allocator, stream: std.Io.net.Stream, config: Config) !void {
    if (config.service == .worker or config.service == .workers) return error.WorkerRequiresService;
    var peer = try acceptPeer(io, allocator, stream, config);
    defer peer.deinit(allocator);
    if (config.service == .sha256)
        try dispatch(io, allocator, stream, config, Sha256{ .limits = config.limits })
    else
        try dispatch(io, allocator, stream, config, Echo{ .registered_name = config.registered_name, .limits = config.limits });
}

fn acceptPeer(io: std.Io, allocator: std.mem.Allocator, stream: std.Io.net.Stream, config: Config) !transport.handshake_io.Peer {
    var challenge_bytes: [4]u8 = undefined;
    io.random(&challenge_bytes);
    return transport.handshake_io.accept(stream, io, allocator, .{
        .node_name = config.node_name,
        .cookie = config.cookie,
        .flags = config.flags | (if (config.service == .worker) worker_service.monitor_flags else @as(u64, 0)),
        .creation = config.creation,
        .challenge = config.challenge orelse @bitCast(challenge_bytes),
        .timeout = config.handshake_timeout,
    });
}

fn serveWorkerConnection(io: std.Io, allocator: std.mem.Allocator, stream: std.Io.net.Stream, config: Config, worker: *worker_service.Worker) !void {
    var peer = try acceptPeer(io, allocator, stream, config);
    defer peer.deinit(allocator);
    defer worker.clearMonitors();
    var reader = stream.reader(io, &.{});
    var writer = stream.writer(io, &.{});
    var demand = actor.Demand.init(1);
    var count: usize = 0;
    while (config.max_messages == 0 or count < config.max_messages) {
        const bytes = transport.deadline.run(io, allocator, config.frame_timeout, transport.distribution_io.readDemandedPacket, .{ allocator, &reader.interface, worker_service.limits.max_packet_bytes, &demand }, dropPacket) catch |err|
            return actualIoError(err, reader.err);
        defer allocator.free(bytes);
        transport.deadline.run(io, allocator, config.write_timeout, worker_service.Worker.handle, .{ worker, allocator, bytes, &peer, &writer.interface }, transport.deadline.dropVoid) catch |err|
            return actualIoError(err, writer.err);
        try demand.grant(1);
        if (bytes.len != 4) count += 1;
    }
}

fn actualIoError(err: anyerror, cause: ?anyerror) anyerror {
    return if (err == error.ReadFailed or err == error.WriteFailed) cause orelse err else err;
}

fn dropPacket(bytes: []u8, allocator: std.mem.Allocator) void {
    allocator.free(bytes);
}

/// Runs an authenticated connection. The handler borrows one packet only for
/// the duration of handle(); a returned response is owned and freed here.
/// A credit is restored only after handling and flushing the reply. Thus a slow
/// handler or blocked write stops all subsequent socket reads, including ticks.
/// Callers needing a custom actor can reuse this loop after authenticating.
pub fn dispatch(io: std.Io, allocator: std.mem.Allocator, stream: std.Io.net.Stream, config: Config, handler: anytype) !void {
    var reader = stream.reader(io, &.{});
    var writer_buffer: [8192]u8 = undefined;
    var writer = stream.writer(io, &writer_buffer);
    var demand = actor.Demand.init(1);
    var handled: usize = 0;
    while (config.max_messages == 0 or handled < config.max_messages) {
        const packet = transport.deadline.run(io, allocator, config.frame_timeout, transport.distribution_io.readDemandedPacket, .{ allocator, &reader.interface, config.limits.max_packet_bytes, &demand }, dropPacket) catch |err|
            return actualIoError(err, reader.err);
        defer allocator.free(packet);
        if (try handler.handle(allocator, packet)) |response| {
            defer allocator.free(response);
            transport.deadline.run(io, allocator, config.write_timeout, transport.distribution_io.writePacket, .{ &writer.interface, response }, transport.deadline.dropVoid) catch |err| return actualIoError(err, writer.err);
            if (packet.len != 4 and config.max_messages != 0) handled += 1;
        }
        try demand.grant(1);
    }
}
