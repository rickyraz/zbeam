const std = @import("std");

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

pub fn encodeName(allocator: std.mem.Allocator, message: Name) (Error || std.mem.Allocator.Error)![]u8 {
    if (message.node_name.len == 0) return error.NodeNameEmpty;
    const payload_len = 13 + message.node_name.len;
    return encodeNPacket(allocator, payload_len, message.flags, null, message.creation, message.node_name);
}

pub fn decodeName(allocator: std.mem.Allocator, payload: []const u8) (Error || std.mem.Allocator.Error)!Name {
    if (payload.len < 14) return error.Truncated;
    if (payload[0] != 'N') return error.UnexpectedTag;
    return .{
        .flags = readU64(payload[1..9]),
        .creation = readU32(payload[9..13]),
        .node_name = try allocator.dupe(u8, payload[13..]),
    };
}

pub fn encodeChallenge(allocator: std.mem.Allocator, message: Challenge) (Error || std.mem.Allocator.Error)![]u8 {
    if (message.node_name.len == 0) return error.NodeNameEmpty;
    const payload_len = 17 + message.node_name.len;
    return encodeNPacket(allocator, payload_len, message.flags, message.challenge, message.creation, message.node_name);
}

pub fn decodeChallenge(allocator: std.mem.Allocator, payload: []const u8) (Error || std.mem.Allocator.Error)!Challenge {
    if (payload.len < 18) return error.Truncated;
    if (payload[0] != 'N') return error.UnexpectedTag;
    return .{
        .flags = readU64(payload[1..9]),
        .challenge = readU32(payload[9..13]),
        .creation = readU32(payload[13..17]),
        .node_name = try allocator.dupe(u8, payload[17..]),
    };
}

pub fn encodeStatus(allocator: std.mem.Allocator, status: Status) std.mem.Allocator.Error![]u8 {
    const text = statusText(status);
    const packet = try allocator.alloc(u8, text.len + 3);
    putU16(packet[0..2], @intCast(text.len + 1));
    packet[2] = 's';
    @memcpy(packet[3..], text);
    return packet;
}

pub fn decodeStatus(payload: []const u8) Error!Status {
    if (payload.len < 2) return error.Truncated;
    if (payload[0] != 's') return error.UnexpectedTag;
    const text = payload[1..];
    inline for (std.meta.tags(Status)) |status| {
        if (std.mem.eql(u8, text, statusText(status))) return status;
    }
    return error.UnexpectedStatus;
}

pub fn encodeReply(allocator: std.mem.Allocator, reply: Reply) std.mem.Allocator.Error![]u8 {
    var payload: [21]u8 = undefined;
    payload[0] = 'r';
    putU32(payload[1..5], reply.challenge);
    @memcpy(payload[5..], &reply.digest);
    return frame(allocator, &payload);
}

pub fn decodeReply(payload: []const u8) Error!Reply {
    if (payload.len != 21) return error.Truncated;
    if (payload[0] != 'r') return error.UnexpectedTag;
    return .{ .challenge = readU32(payload[1..5]), .digest = payload[5..21].* };
}

pub fn encodeAck(allocator: std.mem.Allocator, ack: Ack) std.mem.Allocator.Error![]u8 {
    var payload: [17]u8 = undefined;
    payload[0] = 'a';
    @memcpy(payload[1..], &ack.digest);
    return frame(allocator, &payload);
}

pub fn decodeAck(payload: []const u8) Error!Ack {
    if (payload.len != 17) return error.Truncated;
    if (payload[0] != 'a') return error.UnexpectedTag;
    return .{ .digest = payload[1..17].* };
}

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

pub fn verifyDigest(expected: [16]u8, actual: [16]u8) Error!void {
    if (!std.crypto.timing_safe.eql([16]u8, expected, actual)) return error.InvalidDigest;
}

pub const Initiator = struct {
    state: State = .idle,

    pub const State = enum { idle, name_sent, status_received, challenge_received, reply_sent, connected };
    pub const Event = enum { send_name, receive_status, receive_challenge, send_reply, receive_ack };

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
    @memcpy(packet[index..], node_name);
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

fn readU32(bytes: *const [4]u8) u32 {
    return (@as(u32, bytes[0]) << 24) | (@as(u32, bytes[1]) << 16) |
        (@as(u32, bytes[2]) << 8) | bytes[3];
}

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
