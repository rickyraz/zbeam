const std = @import("std");

/// Handshake frames have a two-octet length prefix, hence the protocol-level
/// length type is `u16`. The lower 1024-byte policy limit rejects unreasonable
/// names without allocating the full theoretical 65,535-byte frame.
pub const max_packet_size: u16 = 1024;

pub const Status = enum { ok, ok_simultaneous, alive, nok, not_allowed };

pub const Name = struct {
    flags: u64,
    creation: u32,
    node_name: []const u8,

    pub fn deinit(self: *Name, allocator: std.mem.Allocator) void {
        allocator.free(self.node_name);
        self.* = undefined;
    }
};

pub const Challenge = struct {
    flags: u64,
    challenge: u32,
    creation: u32,
    node_name: []const u8,

    pub fn deinit(self: *Challenge, allocator: std.mem.Allocator) void {
        allocator.free(self.node_name);
        self.* = undefined;
    }
};

pub const Reply = struct {
    // Challenges are four wire octets (`u32`); MD5 always emits 128 bits,
    // represented exactly as 16 octets rather than a variable slice.
    challenge: u32,
    digest: [16]u8,
};

pub const Ack = struct { digest: [16]u8 };

pub const Error = error{
    PacketTooLarge,
    Truncated,
    TrailingData,
    UnexpectedTag,
    UnexpectedStatus,
    InvalidTransition,
    InvalidDigest,
    NodeNameEmpty,
};

/// Encodes the OTP 23+ `N` name message. Its fixed 15-byte payload is:
/// tag(1) + flags(8) + creation(4) + name_length(2), followed by the name.
pub fn encodeName(allocator: std.mem.Allocator, message: Name) (Error || std.mem.Allocator.Error)![]u8 {
    if (message.node_name.len == 0) return error.NodeNameEmpty;
    const payload_len = 15 + message.node_name.len;
    return encodeNPacket(allocator, payload_len, message.flags, null, message.creation, message.node_name);
}

/// Decodes an unframed `N` name payload and copies the peer name so it remains
/// valid after the transport releases its packet buffer.
pub fn decodeName(allocator: std.mem.Allocator, payload: []const u8) (Error || std.mem.Allocator.Error)!Name {
    if (payload.len < 15) return error.Truncated;
    if (payload[0] != 'N') return error.UnexpectedTag;
    const name_len = readU16(payload[13..15]);
    if (name_len > payload.len - 15) return error.Truncated;
    return .{
        .flags = readU64(payload[1..9]),
        .creation = readU32(payload[9..13]),
        .node_name = try allocator.dupe(u8, payload[15..][0..name_len]),
    };
}

/// Encodes the challenge variant of `N`. It adds one four-octet random
/// challenge to the name layout, giving 19 fixed bytes before the node name.
pub fn encodeChallenge(allocator: std.mem.Allocator, message: Challenge) (Error || std.mem.Allocator.Error)![]u8 {
    if (message.node_name.len == 0) return error.NodeNameEmpty;
    const payload_len = 19 + message.node_name.len;
    return encodeNPacket(allocator, payload_len, message.flags, message.challenge, message.creation, message.node_name);
}

/// Parses and owns the peer's challenge identity after validating its declared
/// name length against the bytes actually received.
pub fn decodeChallenge(allocator: std.mem.Allocator, payload: []const u8) (Error || std.mem.Allocator.Error)!Challenge {
    if (payload.len < 19) return error.Truncated;
    if (payload[0] != 'N') return error.UnexpectedTag;
    const name_len = readU16(payload[17..19]);
    if (name_len > payload.len - 19) return error.Truncated;
    return .{
        .flags = readU64(payload[1..9]),
        .challenge = readU32(payload[9..13]),
        .creation = readU32(payload[13..17]),
        .node_name = try allocator.dupe(u8, payload[19..][0..name_len]),
    };
}

/// Frames the textual status selected by the protocol. Keeping the accepted
/// strings in an enum prevents arbitrary status bytes from entering the FSM.
pub fn encodeStatus(allocator: std.mem.Allocator, status: Status) std.mem.Allocator.Error![]u8 {
    const text = statusText(status);
    const packet = try allocator.alloc(u8, text.len + 3);
    putU16(packet[0..2], @intCast(text.len + 1));
    packet[2] = 's';
    @memcpy(packet[3..], text);
    return packet;
}

/// Maps only protocol-defined status text; unknown values cannot silently
/// become success.
pub fn decodeStatus(payload: []const u8) Error!Status {
    if (payload.len < 2) return error.Truncated;
    if (payload[0] != 's') return error.UnexpectedTag;
    const text = payload[1..];
    inline for (std.meta.tags(Status)) |status| {
        if (std.mem.eql(u8, text, statusText(status))) return status;
    }
    return error.UnexpectedStatus;
}

/// Serializes tag(1) + our challenge(4) + cookie digest(16) = 21 bytes.
/// The peer needs our challenge to produce the reciprocal acknowledgement.
pub fn encodeReply(allocator: std.mem.Allocator, reply: Reply) std.mem.Allocator.Error![]u8 {
    var payload: [21]u8 = undefined;
    payload[0] = 'r';
    putU32(payload[1..5], reply.challenge);
    @memcpy(payload[5..], &reply.digest);
    return frame(allocator, &payload);
}

/// Requires the exact 21-byte shape so extra bytes cannot be smuggled behind
/// an otherwise valid authentication reply.
pub fn decodeReply(payload: []const u8) Error!Reply {
    if (payload.len != 21) return error.Truncated;
    if (payload[0] != 'r') return error.UnexpectedTag;
    return .{ .challenge = readU32(payload[1..5]), .digest = payload[5..21].* };
}

/// Serializes the reciprocal proof as tag(1) + MD5 digest(16) = 17 bytes.
pub fn encodeAck(allocator: std.mem.Allocator, ack: Ack) std.mem.Allocator.Error![]u8 {
    var payload: [17]u8 = undefined;
    payload[0] = 'a';
    @memcpy(payload[1..], &ack.digest);
    return frame(allocator, &payload);
}

/// Requires exactly one tag and one 128-bit digest.
pub fn decodeAck(payload: []const u8) Error!Ack {
    if (payload.len != 17) return error.Truncated;
    if (payload[0] != 'a') return error.UnexpectedTag;
    return .{ .digest = payload[1..17].* };
}

/// Implements the legacy distribution proof MD5(cookie ++ decimal(challenge)).
/// The ten-byte scratch buffer is sufficient for every decimal `u32`
/// (`4294967295` is ten digits). This is compatibility authentication, not a
/// recommendation to use MD5 in new protocols.
pub fn cookieDigest(cookie: []const u8, challenge: u32) [16]u8 {
    var decimal_buffer: [10]u8 = undefined;
    const decimal = std.fmt.bufPrint(&decimal_buffer, "{d}", .{challenge}) catch unreachable;
    var md5 = std.crypto.hash.Md5.init(.{});
    md5.update(cookie);
    md5.update(decimal);
    var result: [16]u8 = undefined;
    md5.final(&result);
    return result;
}

/// Uses constant-time comparison so mismatch position does not leak through
/// ordinary early-exit timing behavior.
pub fn verifyDigest(expected: [16]u8, actual: [16]u8) Error!void {
    if (!std.crypto.timing_safe.eql([16]u8, expected, actual)) return error.InvalidDigest;
}

pub const Initiator = struct {
    state: State = .idle,

    pub const State = enum { idle, name_sent, status_received, challenge_received, reply_sent, connected };
    pub const Event = enum { send_name, receive_status, receive_challenge, send_reply, receive_ack };

    /// Makes legal ordering explicit. Authentication messages are meaningful
    /// only after their prerequisites, so out-of-order I/O fails closed.
    pub fn advance(self: *Initiator, event: Event) Error!void {
        self.state = switch (self.state) {
            .idle => if (event == .send_name) .name_sent else return error.InvalidTransition,
            .name_sent => if (event == .receive_status) .status_received else return error.InvalidTransition,
            .status_received => if (event == .receive_challenge) .challenge_received else return error.InvalidTransition,
            .challenge_received => if (event == .send_reply) .reply_sent else return error.InvalidTransition,
            .reply_sent => if (event == .receive_ack) .connected else return error.InvalidTransition,
            .connected => return error.InvalidTransition,
        };
    }
};

pub const Acceptor = struct {
    state: State = .idle,

    pub const State = enum { idle, name_received, status_sent, challenge_sent, reply_received, connected };
    pub const Event = enum { receive_name, send_status, send_challenge, receive_reply, send_ack };

    /// Mirrors the initiator from the accepting side and rejects skipped or
    /// replayed steps before the transport treats the peer as connected.
    pub fn advance(self: *Acceptor, event: Event) Error!void {
        self.state = switch (self.state) {
            .idle => if (event == .receive_name) .name_received else return error.InvalidTransition,
            .name_received => if (event == .send_status) .status_sent else return error.InvalidTransition,
            .status_sent => if (event == .send_challenge) .challenge_sent else return error.InvalidTransition,
            .challenge_sent => if (event == .receive_reply) .reply_received else return error.InvalidTransition,
            .reply_received => if (event == .send_ack) .connected else return error.InvalidTransition,
            .connected => return error.InvalidTransition,
        };
    }
};

/// Shared constructor keeps the nearly identical NAME and CHALLENGE layouts
/// from drifting. All multibyte fields are emitted big-endian as wire values.
fn encodeNPacket(allocator: std.mem.Allocator, payload_len: usize, flags: u64, challenge: ?u32, creation: u32, node_name: []const u8) (Error || std.mem.Allocator.Error)![]u8 {
    if (payload_len > max_packet_size) return error.PacketTooLarge;
    const packet = try allocator.alloc(u8, payload_len + 2);
    putU16(packet[0..2], @intCast(payload_len));
    packet[2] = 'N';
    putU64(packet[3..11], flags);
    var index: usize = 11;
    if (challenge) |value| {
        putU32(packet[index..][0..4], value);
        index += 4;
    }
    putU32(packet[index..][0..4], creation);
    index += 4;
    putU16(packet[index..][0..2], @intCast(node_name.len));
    index += 2;
    @memcpy(packet[index..][0..node_name.len], node_name);
    return packet;
}

fn frame(allocator: std.mem.Allocator, payload: []const u8) std.mem.Allocator.Error![]u8 {
    const packet = try allocator.alloc(u8, payload.len + 2);
    putU16(packet[0..2], @intCast(payload.len));
    @memcpy(packet[2..], payload);
    return packet;
}

fn statusText(status: Status) []const u8 {
    return switch (status) {
        .ok => "ok",
        .ok_simultaneous => "ok_simultaneous",
        .alive => "alive",
        .nok => "nok",
        .not_allowed => "not_allowed",
    };
}

fn putU16(out: *[2]u8, value: u16) void {
    out.* = .{ @intCast(value >> 8), @truncate(value) };
}

fn putU32(out: *[4]u8, value: u32) void {
    out.* = .{ @intCast(value >> 24), @truncate(value >> 16), @truncate(value >> 8), @truncate(value) };
}

fn putU64(out: *[8]u8, value: u64) void {
    out.* = .{
        @intCast(value >> 56),  @truncate(value >> 48), @truncate(value >> 40), @truncate(value >> 32),
        @truncate(value >> 24), @truncate(value >> 16), @truncate(value >> 8),  @truncate(value),
    };
}

fn readU16(bytes: *const [2]u8) u16 {
    return (@as(u16, bytes[0]) << 8) | bytes[1];
}

fn readU32(bytes: *const [4]u8) u32 {
    return (@as(u32, bytes[0]) << 24) | (@as(u32, bytes[1]) << 16) |
        (@as(u32, bytes[2]) << 8) | bytes[3];
}

/// Reconstructs a network-order 64-bit flag word one octet at a time. Each
/// iteration shifts existing bits by eight because one input element is `u8`.
fn readU64(bytes: *const [8]u8) u64 {
    var value: u64 = 0;
    for (bytes) |byte| value = (value << 8) | byte;
    return value;
}

test "initiating and accepting FSMs complete the same deterministic handshake" {
    const allocator = std.testing.allocator;
    const cookie = "secret";
    const initiator_challenge: u32 = 1234;
    const acceptor_challenge: u32 = 5678;

    var initiator: Initiator = .{};
    var acceptor: Acceptor = .{};
    try initiator.advance(.send_name);
    try acceptor.advance(.receive_name);
    try acceptor.advance(.send_status);
    try initiator.advance(.receive_status);
    try acceptor.advance(.send_challenge);
    try initiator.advance(.receive_challenge);

    const reply_packet = try encodeReply(allocator, .{
        .challenge = initiator_challenge,
        .digest = cookieDigest(cookie, acceptor_challenge),
    });
    defer allocator.free(reply_packet);
    const reply = try decodeReply(reply_packet[2..]);
    try verifyDigest(cookieDigest(cookie, acceptor_challenge), reply.digest);
    try initiator.advance(.send_reply);
    try acceptor.advance(.receive_reply);

    const ack_packet = try encodeAck(allocator, .{ .digest = cookieDigest(cookie, initiator_challenge) });
    defer allocator.free(ack_packet);
    const ack = try decodeAck(ack_packet[2..]);
    try verifyDigest(cookieDigest(cookie, initiator_challenge), ack.digest);
    try acceptor.advance(.send_ack);
    try initiator.advance(.receive_ack);
    try std.testing.expectEqual(Initiator.State.connected, initiator.state);
    try std.testing.expectEqual(Acceptor.State.connected, acceptor.state);
}

test "handshake rejects invalid transitions and digests" {
    var initiator: Initiator = .{};
    try std.testing.expectError(error.InvalidTransition, initiator.advance(.receive_status));
    try std.testing.expectError(error.InvalidDigest, verifyDigest(@splat(1), @splat(2)));
}
