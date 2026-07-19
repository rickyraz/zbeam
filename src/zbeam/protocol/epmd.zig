const std = @import("std");

// EPMD fields use the widths fixed by the protocol: TCP ports and message
// lengths are 16-bit, while request/response tags are single 8-bit octets.
// These widths are wire compatibility requirements, not local optimizations.
pub const default_port: u16 = 4369;
pub const normal_node: u8 = 77;
pub const tcp_ip_v4: u8 = 0;
pub const highest_version: u16 = 6;
pub const lowest_version: u16 = 6;

pub const alive2_req: u8 = 120;
pub const alive2_resp: u8 = 121;
pub const alive2_x_resp: u8 = 118;
pub const port_please2_req: u8 = 122;
pub const port2_resp: u8 = 119;

pub const AliveOptions = struct {
    port: u16,
    node_name: []const u8,
    node_type: u8 = normal_node,
    protocol: u8 = tcp_ip_v4,
    highest: u16 = highest_version,
    lowest: u16 = lowest_version,
    extra: []const u8 = "",
};

pub const AliveResult = struct { creation: u32 };

pub const NodeInfo = struct {
    port: u16,
    node_type: u8,
    protocol: u8,
    highest: u16,
    lowest: u16,
    node_name: []const u8,
    extra: []const u8,

    pub fn deinit(self: *NodeInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.node_name);
        allocator.free(self.extra);
        self.* = undefined;
    }
};

pub const Error = error{
    NameTooLong,
    ExtraTooLong,
    MessageTooLong,
    Truncated,
    UnexpectedTag,
    RegistrationFailed,
    NodeNotFound,
    LimitExceeded,
    InvalidResponse,
};

/// Builds ALIVE2_REQ, which tells EPMD which distribution port belongs to a
/// node name. The leading `u16` counts the payload only; therefore the allocated
/// packet is payload + two framing octets.
pub fn encodeAlive2(allocator: std.mem.Allocator, options: AliveOptions) (Error || std.mem.Allocator.Error)![]u8 {
    const name_len = std.math.cast(u16, options.node_name.len) orelse return error.NameTooLong;
    const extra_len = std.math.cast(u16, options.extra.len) orelse return error.ExtraTooLong;
    const payload_len = 13 + @as(usize, name_len) + @as(usize, extra_len);
    const framed_len = std.math.cast(u16, payload_len) orelse return error.MessageTooLong;
    const bytes = try allocator.alloc(u8, payload_len + 2);
    var index: usize = 0;
    putU16(bytes, &index, framed_len);
    bytes[index] = alive2_req;
    index += 1;
    putU16(bytes, &index, options.port);
    bytes[index] = options.node_type;
    bytes[index + 1] = options.protocol;
    index += 2;
    putU16(bytes, &index, options.highest);
    putU16(bytes, &index, options.lowest);
    putU16(bytes, &index, name_len);
    @memcpy(bytes[index..][0..name_len], options.node_name);
    index += name_len;
    putU16(bytes, &index, extra_len);
    @memcpy(bytes[index..][0..extra_len], options.extra);
    return bytes;
}

/// Builds PORT_PLEASE2_REQ for name-to-port lookup. The request carries no
/// explicit name length because the outer 16-bit frame already delimits it.
pub fn encodePortPlease2(allocator: std.mem.Allocator, node_name: []const u8) (Error || std.mem.Allocator.Error)![]u8 {
    const payload_len = 1 + node_name.len;
    const framed_len = std.math.cast(u16, payload_len) orelse return error.NameTooLong;
    const bytes = try allocator.alloc(u8, payload_len + 2);
    var index: usize = 0;
    putU16(bytes, &index, framed_len);
    bytes[index] = port_please2_req;
    @memcpy(bytes[index + 1 ..], node_name);
    return bytes;
}

/// Accepts both historical 16-bit and extended 32-bit creation responses.
/// Creation distinguishes node incarnations, so truncating the extended form
/// could make a restarted node look like an old one.
pub fn decodeAliveResponse(bytes: []const u8) Error!AliveResult {
    if (bytes.len < 2) return error.Truncated;
    if (bytes[1] != 0) return error.RegistrationFailed;
    return switch (bytes[0]) {
        alive2_resp => if (bytes.len == 4)
            .{ .creation = readU16(bytes[2..4]) }
        else
            error.InvalidResponse,
        alive2_x_resp => if (bytes.len == 6)
            .{ .creation = readU32(bytes[2..6]) }
        else
            error.InvalidResponse,
        else => error.UnexpectedTag,
    };
}

/// Parses a complete PORT2_RESP into owned metadata. Lengths are checked before
/// copying because EPMD is a network trust boundary even on typical localhost
/// deployments; `max_extra` also caps peer-controlled allocation.
pub fn decodePort2Response(allocator: std.mem.Allocator, bytes: []const u8, max_extra: u16) (Error || std.mem.Allocator.Error)!NodeInfo {
    if (bytes.len < 2) return error.Truncated;
    if (bytes[0] != port2_resp) return error.UnexpectedTag;
    if (bytes[1] != 0) return error.NodeNotFound;
    if (bytes.len < 12) return error.Truncated;

    var index: usize = 2;
    const port = consumeU16(bytes, &index) catch return error.Truncated;
    const node_type = bytes[index];
    const protocol = bytes[index + 1];
    index += 2;
    const highest = consumeU16(bytes, &index) catch return error.Truncated;
    const lowest = consumeU16(bytes, &index) catch return error.Truncated;
    const name_len = consumeU16(bytes, &index) catch return error.Truncated;
    if (name_len > bytes.len - index) return error.Truncated;
    const node_name = try allocator.dupe(u8, bytes[index..][0..name_len]);
    errdefer allocator.free(node_name);
    index += name_len;
    const extra_len = consumeU16(bytes, &index) catch return error.Truncated;
    if (extra_len > max_extra) return error.LimitExceeded;
    if (extra_len > bytes.len - index) return error.Truncated;
    const extra = try allocator.dupe(u8, bytes[index..][0..extra_len]);
    errdefer allocator.free(extra);
    index += extra_len;
    if (index != bytes.len) return error.InvalidResponse;

    return .{
        .port = port,
        .node_type = node_type,
        .protocol = protocol,
        .highest = highest,
        .lowest = lowest,
        .node_name = node_name,
        .extra = extra,
    };
}

/// Writes a 16-bit integer most-significant octet first, as EPMD specifies
/// network byte order. Advancing the shared index keeps layout arithmetic local.
fn putU16(bytes: []u8, index: *usize, value: u16) void {
    bytes[index.*] = @intCast(value >> 8);
    bytes[index.* + 1] = @truncate(value);
    index.* += 2;
}

fn readU16(bytes: *const [2]u8) u16 {
    return (@as(u16, bytes[0]) << 8) | bytes[1];
}

fn readU32(bytes: *const [4]u8) u32 {
    return (@as(u32, bytes[0]) << 24) | (@as(u32, bytes[1]) << 16) |
        (@as(u32, bytes[2]) << 8) | bytes[3];
}

fn consumeU16(bytes: []const u8, index: *usize) error{Truncated}!u16 {
    if (bytes.len - index.* < 2) return error.Truncated;
    defer index.* += 2;
    return readU16(bytes[index.*..][0..2]);
}

test "EPMD request codecs include the two-byte message length" {
    const allocator = std.testing.allocator;
    const alive = try encodeAlive2(allocator, .{ .port = 1234, .node_name = "zbeam" });
    defer allocator.free(alive);
    try std.testing.expectEqual(@as(u16, @intCast(alive.len - 2)), readU16(alive[0..2]));
    try std.testing.expectEqual(alive2_req, alive[2]);

    const lookup = try encodePortPlease2(allocator, "zbeam");
    defer allocator.free(lookup);
    try std.testing.expectEqual(port_please2_req, lookup[2]);
}

test "EPMD response codecs reject errors and preserve node metadata" {
    try std.testing.expectEqual(@as(u32, 7), (try decodeAliveResponse(&.{ alive2_x_resp, 0, 0, 0, 0, 7 })).creation);
    try std.testing.expectError(error.RegistrationFailed, decodeAliveResponse(&.{ alive2_resp, 1, 0, 0 }));

    const response = [_]u8{
        port2_resp, 0,   0x12, 0x34, normal_node, tcp_ip_v4, 0, 6, 0, 5, 0, 5,
        'z',        'b', 'e',  'a',  'm',         0,         1, 9,
    };
    var info = try decodePort2Response(std.testing.allocator, &response, 16);
    defer info.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u16, 0x1234), info.port);
    try std.testing.expectEqualStrings("zbeam", info.node_name);
    try std.testing.expectEqualSlices(u8, &.{9}, info.extra);
}
