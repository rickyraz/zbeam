const std = @import("std");
const handshake = @import("zbeam-protocol").handshake;

pub const Config = struct {
    node_name: []const u8,
    cookie: []const u8,
    flags: u64,
    creation: u32,
    challenge: u32,
    max_packet_size: u16 = handshake.max_packet_size,
};

pub const Peer = struct {
    node_name: []const u8,
    flags: u64,
    creation: u32,

    pub fn deinit(self: *Peer, allocator: std.mem.Allocator) void {
        allocator.free(self.node_name);
        self.* = undefined;
    }
};

pub fn initiate(stream: std.Io.net.Stream, io: std.Io, allocator: std.mem.Allocator, config: Config) !Peer {
    var reader_buffer: [2048]u8 = undefined;
    var writer_buffer: [2048]u8 = undefined;
    var stream_reader = stream.reader(io, &reader_buffer);
    var stream_writer = stream.writer(io, &writer_buffer);
    const reader = &stream_reader.interface;
    const writer = &stream_writer.interface;
    var fsm: handshake.Initiator = .{};

    const name_packet = try handshake.encodeName(allocator, .{
        .flags = config.flags,
        .creation = config.creation,
        .node_name = config.node_name,
    });
    defer allocator.free(name_packet);
    try writePacket(writer, name_packet);
    try fsm.advance(.send_name);

    const status_payload = try readPacket(allocator, reader, config.max_packet_size);
    defer allocator.free(status_payload);
    const status = try handshake.decodeStatus(status_payload);
    if (status != .ok and status != .ok_simultaneous) return error.ConnectionRejected;
    try fsm.advance(.receive_status);

    const challenge_payload = try readPacket(allocator, reader, config.max_packet_size);
    defer allocator.free(challenge_payload);
    var peer_challenge = try handshake.decodeChallenge(allocator, challenge_payload);
    errdefer peer_challenge.deinit(allocator);
    try fsm.advance(.receive_challenge);

    const reply_packet = try handshake.encodeReply(allocator, .{
        .challenge = config.challenge,
        .digest = handshake.cookieDigest(config.cookie, peer_challenge.challenge),
    });
    defer allocator.free(reply_packet);
    try writePacket(writer, reply_packet);
    try fsm.advance(.send_reply);

    const ack_payload = try readPacket(allocator, reader, config.max_packet_size);
    defer allocator.free(ack_payload);
    const ack = try handshake.decodeAck(ack_payload);
    try handshake.verifyDigest(handshake.cookieDigest(config.cookie, config.challenge), ack.digest);
    try fsm.advance(.receive_ack);

    const peer = Peer{
        .node_name = peer_challenge.node_name,
        .flags = peer_challenge.flags,
        .creation = peer_challenge.creation,
    };
    peer_challenge = undefined;
    return peer;
}

pub fn accept(stream: std.Io.net.Stream, io: std.Io, allocator: std.mem.Allocator, config: Config) !Peer {
    var reader_buffer: [2048]u8 = undefined;
    var writer_buffer: [2048]u8 = undefined;
    var stream_reader = stream.reader(io, &reader_buffer);
    var stream_writer = stream.writer(io, &writer_buffer);
    const reader = &stream_reader.interface;
    const writer = &stream_writer.interface;
    var fsm: handshake.Acceptor = .{};

    const name_payload = try readPacket(allocator, reader, config.max_packet_size);
    defer allocator.free(name_payload);
    var peer_name = try handshake.decodeName(allocator, name_payload);
    errdefer peer_name.deinit(allocator);
    try fsm.advance(.receive_name);

    const status_packet = try handshake.encodeStatus(allocator, .ok);
    defer allocator.free(status_packet);
    try writePacket(writer, status_packet);
    try fsm.advance(.send_status);

    const challenge_packet = try handshake.encodeChallenge(allocator, .{
        .flags = config.flags,
        .challenge = config.challenge,
        .creation = config.creation,
        .node_name = config.node_name,
    });
    defer allocator.free(challenge_packet);
    try writePacket(writer, challenge_packet);
    try fsm.advance(.send_challenge);

    const reply_payload = try readPacket(allocator, reader, config.max_packet_size);
    defer allocator.free(reply_payload);
    const reply = try handshake.decodeReply(reply_payload);
    try handshake.verifyDigest(handshake.cookieDigest(config.cookie, config.challenge), reply.digest);
    try fsm.advance(.receive_reply);

    const ack_packet = try handshake.encodeAck(allocator, .{
        .digest = handshake.cookieDigest(config.cookie, reply.challenge),
    });
    defer allocator.free(ack_packet);
    try writePacket(writer, ack_packet);
    try fsm.advance(.send_ack);

    const peer = Peer{
        .node_name = peer_name.node_name,
        .flags = peer_name.flags,
        .creation = peer_name.creation,
    };
    peer_name = undefined;
    return peer;
}

fn readPacket(allocator: std.mem.Allocator, reader: *std.Io.Reader, max_size: u16) ![]u8 {
    var length_bytes: [2]u8 = undefined;
    try reader.readSliceAll(&length_bytes);
    const length = (@as(u16, length_bytes[0]) << 8) | length_bytes[1];
    if (length == 0 or length > max_size) return error.PacketTooLarge;
    const payload = try allocator.alloc(u8, length);
    errdefer allocator.free(payload);
    try reader.readSliceAll(payload);
    return payload;
}

fn writePacket(writer: *std.Io.Writer, packet: []const u8) !void {
    try writer.writeAll(packet);
    try writer.flush();
}
