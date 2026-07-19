const std = @import("std");
const etf = @import("zbeam-etf");

pub const pass_through: u8 = 112;
pub const reg_send: i64 = 6;
pub const send: i64 = 2;

pub const Limits = struct {
    max_packet_bytes: u32 = 16 * 1024 * 1024,
    etf: etf.Limits = .{},
};

pub const Error = error{
    Truncated,
    LengthMismatch,
    PacketTooLarge,
    UnexpectedHeader,
    MissingPayload,
    InvalidControl,
};

pub const Packet = union(enum) {
    tick,
    message: Message,

    pub fn deinit(self: *Packet, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .tick => {},
            .message => |*message| message.deinit(allocator),
        }
        self.* = undefined;
    }
};

pub const Message = struct {
    control: etf.Term,
    /// Borrowed from the packet bytes passed to `decodePacket`.
    payload_etf: ?[]const u8,

    pub fn deinit(self: *Message, allocator: std.mem.Allocator) void {
        self.control.deinit(allocator);
        self.* = undefined;
    }

    pub fn decodePayload(self: *const Message, allocator: std.mem.Allocator, limits: etf.Limits) !etf.Term {
        return etf.decode(allocator, self.payload_etf orelse return error.MissingPayload, limits);
    }
};

pub fn decodePacket(allocator: std.mem.Allocator, packet: []const u8, limits: Limits) !Packet {
    if (packet.len < 4) return error.Truncated;
    const declared = readU32(packet[0..4]);
    if (declared > limits.max_packet_bytes) return error.PacketTooLarge;
    if (declared != packet.len - 4) return error.LengthMismatch;
    if (declared == 0) return .tick;
    if (packet[4] != pass_through) return error.UnexpectedHeader;

    const terms = packet[5..];
    var control = try etf.decodePrefix(allocator, terms, limits.etf);
    errdefer control.term.deinit(allocator);
    const remaining = terms[control.bytes_read..];
    return .{ .message = .{
        .control = control.term,
        .payload_etf = if (remaining.len == 0) null else remaining,
    } };
}

pub fn encodePacket(allocator: std.mem.Allocator, control: *const etf.Term, payload: ?*const etf.Term) ![]u8 {
    const control_bytes = try etf.encode(allocator, control);
    defer allocator.free(control_bytes);
    const payload_bytes = if (payload) |value| try etf.encode(allocator, value) else null;
    defer if (payload_bytes) |bytes| allocator.free(bytes);

    const data_len = 1 + control_bytes.len + if (payload_bytes) |bytes| bytes.len else 0;
    const length = std.math.cast(u32, data_len) orelse return error.PacketTooLarge;
    const packet = try allocator.alloc(u8, data_len + 4);
    putU32(packet[0..4], length);
    packet[4] = pass_through;
    @memcpy(packet[5..][0..control_bytes.len], control_bytes);
    if (payload_bytes) |bytes| @memcpy(packet[5 + control_bytes.len ..], bytes);
    return packet;
}

pub fn tickPacket() [4]u8 {
    return @splat(0);
}

pub fn regSendDestination(control: *const etf.Term) Error!struct { from: etf.Pid, name: []const u8 } {
    if (control.* != .tuple or control.tuple.len != 4) return error.InvalidControl;
    const fields = control.tuple;
    if (fields[0] != .integer or fields[0].integer != reg_send) return error.InvalidControl;
    if (fields[1] != .pid or fields[3] != .atom) return error.InvalidControl;
    return .{ .from = fields[1].pid, .name = fields[3].atom };
}

fn readU32(bytes: *const [4]u8) u32 {
    return (@as(u32, bytes[0]) << 24) | (@as(u32, bytes[1]) << 16) |
        (@as(u32, bytes[2]) << 8) | bytes[3];
}

fn putU32(out: *[4]u8, value: u32) void {
    out.* = .{ @intCast(value >> 24), @truncate(value >> 16), @truncate(value >> 8), @truncate(value) };
}

test "distribution packet separates control and payload ETF terms" {
    const allocator = std.testing.allocator;
    var control_items = [_]etf.Term{ .{ .integer = send }, .{ .atom = "" }, .{ .pid = .{ .node = "n@h", .id = 1, .serial = 0, .creation = 2 } } };
    var control = etf.Term{ .tuple = &control_items };
    var payload = etf.Term{ .atom = "hello" };
    const bytes = try encodePacket(allocator, &control, &payload);
    defer allocator.free(bytes);

    var decoded = try decodePacket(allocator, bytes, .{});
    defer decoded.deinit(allocator);
    try std.testing.expect(decoded == .message);
    var decoded_payload = try decoded.message.decodePayload(allocator, .{});
    defer decoded_payload.deinit(allocator);
    try std.testing.expect(decoded_payload == .atom);
    try std.testing.expectEqualStrings("hello", decoded_payload.atom);
}
