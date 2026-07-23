const std = @import("std");
const types = @import("term.zig");

pub const Term = types.Term;
pub const Pid = types.Pid;

/// Every standalone External Term Format value starts with decimal 131
/// (`0x83`). It is one octet (`u8`) because ETF defines tags and the version
/// marker as byte-sized wire discriminants, not because 8 bits are arbitrary.
/// ETF specification: https://www.erlang.org/docs/27/apps/erts/erl_ext_dist.html
pub const version: u8 = 131;

/// Bounds are checked before allocation. A network peer controls encoded
/// lengths, so trusting them would let a tiny packet request excessive memory
/// or recursion depth. Allocation guidance: https://cwe.mitre.org/data/definitions/789.html
pub const Limits = struct {
    max_depth: u16 = 64,
    max_collection_len: u32 = 1_048_576,
    max_binary_bytes: u32 = 16 * 1024 * 1024,
    max_atom_bytes: u16 = 255,
};

pub const DecodeError = error{
    InvalidVersion,
    TrailingData,
    Truncated,
    UnknownTag,
    LimitExceeded,
    InvalidAtom,
    InvalidListTail,
};

pub const EncodeError = error{
    IntegerOutOfRange,
    AtomTooLong,
    CollectionTooLarge,
};

// ETF tags are one-octet protocol constants. Their numeric values come from
// the Erlang external format specification and must never be renumbered.
const small_integer_ext: u8 = 97;
const integer_ext = 98;
const small_tuple_ext = 104;
const large_tuple_ext = 105;
const nil_ext = 106;
const string_ext = 107;
const list_ext = 108;
const binary_ext = 109;
const atom_utf8_ext = 118;
const small_atom_utf8_ext = 119;
const new_pid_ext = 88;

pub const Decoded = struct {
    term: Term,
    bytes_read: usize,
};

/// Decodes exactly one ETF value and reports how many bytes it consumed.
/// Distribution packets concatenate control and payload terms, so requiring
/// end-of-buffer here would make that valid framing impossible to separate.
pub fn decodePrefix(allocator: std.mem.Allocator, bytes: []const u8, limits: Limits) (DecodeError || std.mem.Allocator.Error)!Decoded {
    var cursor = Cursor{ .bytes = bytes };
    if (try cursor.readByte() != version) return error.InvalidVersion;
    return .{
        .term = try decodeValue(allocator, &cursor, limits, 0),
        .bytes_read = cursor.index,
    };
}

/// Decodes one complete ETF value. Rejecting trailing bytes prevents callers
/// from accidentally authenticating or routing only a valid prefix.
pub fn decode(allocator: std.mem.Allocator, bytes: []const u8, limits: Limits) (DecodeError || std.mem.Allocator.Error)!Term {
    var decoded = try decodePrefix(allocator, bytes, limits);
    errdefer decoded.term.deinit(allocator);
    if (decoded.bytes_read != bytes.len) return error.TrailingData;
    return decoded.term;
}

/// Encodes an owned term into canonical bytes for the supported subset.
/// The returned slice belongs to the caller; a growing buffer is used because
/// nested ETF values do not have a cheap fixed size before traversal.
pub fn encode(allocator: std.mem.Allocator, term: *const Term) (EncodeError || std.mem.Allocator.Error)![]u8 {
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);
    try output.append(allocator, version);
    try encodeValue(allocator, &output, term);
    return output.toOwnedSlice(allocator);
}

/// Dispatches on the one-byte ETF tag. `depth` increases only when entering a
/// nested value, making the recursion ceiling independent of total byte size.
fn decodeValue(allocator: std.mem.Allocator, cursor: *Cursor, limits: Limits, depth: u16) (DecodeError || std.mem.Allocator.Error)!Term {
    if (depth >= limits.max_depth) return error.LimitExceeded;
    const tag = try cursor.readByte();
    return switch (tag) {
        small_integer_ext => .{ .integer = try cursor.readByte() },
        integer_ext => .{ .integer = try cursor.readI32() },
        small_atom_utf8_ext => decodeAtom(allocator, cursor, try cursor.readByte(), limits),
        atom_utf8_ext => decodeAtom(allocator, cursor, try cursor.readU16(), limits),
        small_tuple_ext => decodeSequence(.tuple, allocator, cursor, try cursor.readByte(), limits, depth),
        large_tuple_ext => decodeSequence(.tuple, allocator, cursor, try cursor.readU32(), limits, depth),
        nil_ext => .nil,
        string_ext => decodeString(allocator, cursor, limits),
        list_ext => decodeList(allocator, cursor, limits, depth),
        binary_ext => decodeBinary(allocator, cursor, limits),
        new_pid_ext => decodePid(allocator, cursor, limits, depth),
        else => error.UnknownTag,
    };
}

/// Copies and validates atom text. UTF-8 validation matters because these tags
/// promise UTF-8 on the wire; accepting arbitrary bytes would violate ETF.
fn decodeAtom(allocator: std.mem.Allocator, cursor: *Cursor, length: u16, limits: Limits) (DecodeError || std.mem.Allocator.Error)!Term {
    if (length > limits.max_atom_bytes) return error.LimitExceeded;
    const source = try cursor.take(length);
    if (!std.unicode.utf8ValidateSlice(source)) return error.InvalidAtom;
    return .{ .atom = try allocator.dupe(u8, source) };
}

fn decodeBinary(allocator: std.mem.Allocator, cursor: *Cursor, limits: Limits) (DecodeError || std.mem.Allocator.Error)!Term {
    const length = try cursor.readU32();
    if (length > limits.max_binary_bytes) return error.LimitExceeded;
    return .{ .binary = try allocator.dupe(u8, try cursor.take(length)) };
}

/// Shared tuple/list element decoder. Each item needs at least one tag byte,
/// so reject an obviously truncated collection before allocating its item array.
/// A proper list reserves one additional byte for its NIL_EXT tail. Partial
/// initialization is unwound so a malformed child cannot leak the children
/// decoded before it.
fn decodeSequence(comptime tag: std.meta.Tag(Term), allocator: std.mem.Allocator, cursor: *Cursor, length: u32, limits: Limits, depth: u16) (DecodeError || std.mem.Allocator.Error)!Term {
    if (length > limits.max_collection_len) return error.LimitExceeded;
    const item_count = std.math.cast(usize, length) orelse return error.LimitExceeded;
    const trailing_min_bytes: usize = if (tag == .list) 1 else 0;
    const remaining = cursor.bytes.len - cursor.index;
    if (item_count > remaining or trailing_min_bytes > remaining - item_count) return error.Truncated;
    const items = try allocator.alloc(Term, item_count);
    var initialized: usize = 0;
    errdefer {
        for (items[0..initialized]) |*item| item.deinit(allocator);
        allocator.free(items);
    }
    while (initialized < items.len) : (initialized += 1) {
        items[initialized] = try decodeValue(allocator, cursor, limits, depth + 1);
    }
    return @unionInit(Term, @tagName(tag), items);
}

fn decodeString(allocator: std.mem.Allocator, cursor: *Cursor, limits: Limits) (DecodeError || std.mem.Allocator.Error)!Term {
    const length = try cursor.readU16();
    if (length > limits.max_collection_len) return error.LimitExceeded;
    const bytes = try cursor.take(length);
    const items = try allocator.alloc(Term, length);
    errdefer allocator.free(items);
    for (bytes, items) |byte, *item| item.* = .{ .integer = byte };
    return .{ .list = items };
}

/// This subset models only proper lists, therefore the final ETF tail must be
/// NIL_EXT. Improper lists are rejected rather than represented ambiguously.
fn decodeList(allocator: std.mem.Allocator, cursor: *Cursor, limits: Limits, depth: u16) (DecodeError || std.mem.Allocator.Error)!Term {
    const length = try cursor.readU32();
    var result = try decodeSequence(.list, allocator, cursor, length, limits, depth);
    errdefer result.deinit(allocator);
    const tail = try decodeValue(allocator, cursor, limits, depth + 1);
    if (tail != .nil) {
        var owned_tail = tail;
        owned_tail.deinit(allocator);
        return error.InvalidListTail;
    }
    return result;
}

fn decodePid(allocator: std.mem.Allocator, cursor: *Cursor, limits: Limits, depth: u16) (DecodeError || std.mem.Allocator.Error)!Term {
    var node = try decodeValue(allocator, cursor, limits, depth + 1);
    errdefer node.deinit(allocator);
    if (node != .atom) return error.InvalidAtom;
    const node_bytes = node.atom;
    node = undefined;
    return .{ .pid = .{
        .node = node_bytes,
        .id = try cursor.readU32(),
        .serial = try cursor.readU32(),
        .creation = try cursor.readU32(),
    } };
}

/// Chooses the smallest standard ETF representation that preserves the value:
/// one payload byte for 0..255, four bytes for signed i32, and compact tuple,
/// atom, or byte-list tags when their one-byte/two-byte length fields permit.
fn encodeValue(allocator: std.mem.Allocator, output: *std.ArrayList(u8), term: *const Term) (EncodeError || std.mem.Allocator.Error)!void {
    switch (term.*) {
        .integer => |value| {
            if (value >= 0 and value <= 255) {
                try output.append(allocator, small_integer_ext);
                try output.append(allocator, @intCast(value));
            } else {
                const narrowed = std.math.cast(i32, value) orelse return error.IntegerOutOfRange;
                try output.append(allocator, integer_ext);
                try appendU32(allocator, output, @bitCast(narrowed));
            }
        },
        .atom => |bytes| try encodeAtom(allocator, output, bytes),
        .binary => |bytes| {
            const length = std.math.cast(u32, bytes.len) orelse return error.CollectionTooLarge;
            try output.append(allocator, binary_ext);
            try appendU32(allocator, output, length);
            try output.appendSlice(allocator, bytes);
        },
        .tuple => |items| {
            if (items.len <= 255) {
                try output.append(allocator, small_tuple_ext);
                try output.append(allocator, @intCast(items.len));
            } else {
                const length = std.math.cast(u32, items.len) orelse return error.CollectionTooLarge;
                try output.append(allocator, large_tuple_ext);
                try appendU32(allocator, output, length);
            }
            for (items) |*item| try encodeValue(allocator, output, item);
        },
        .list => |items| {
            if (items.len <= std.math.maxInt(u16) and isByteList(items)) {
                try output.append(allocator, string_ext);
                try appendU16(allocator, output, @intCast(items.len));
                for (items) |item| try output.append(allocator, @intCast(item.integer));
            } else {
                const length = std.math.cast(u32, items.len) orelse return error.CollectionTooLarge;
                try output.append(allocator, list_ext);
                try appendU32(allocator, output, length);
                for (items) |*item| try encodeValue(allocator, output, item);
                try output.append(allocator, nil_ext);
            }
        },
        .pid => |pid| {
            try output.append(allocator, new_pid_ext);
            var node = Term{ .atom = pid.node };
            try encodeValue(allocator, output, &node);
            try appendU32(allocator, output, pid.id);
            try appendU32(allocator, output, pid.serial);
            try appendU32(allocator, output, pid.creation);
        },
        .nil => try output.append(allocator, nil_ext),
    }
}

fn isByteList(items: []const Term) bool {
    for (items) |item| switch (item) {
        .integer => |value| if (value < 0 or value > 255) return false,
        else => return false,
    };
    return true;
}

fn encodeAtom(allocator: std.mem.Allocator, output: *std.ArrayList(u8), bytes: []const u8) (EncodeError || std.mem.Allocator.Error)!void {
    if (bytes.len > std.math.maxInt(u16)) return error.AtomTooLong;
    if (bytes.len <= 255) {
        try output.append(allocator, small_atom_utf8_ext);
        try output.append(allocator, @intCast(bytes.len));
    } else {
        try output.append(allocator, atom_utf8_ext);
        try appendU16(allocator, output, @intCast(bytes.len));
    }
    try output.appendSlice(allocator, bytes);
}

// ETF multibyte integers are big-endian (network byte order). Shifting by
// eight moves one octet at a time; truncation keeps the low eight bits.
fn appendU16(allocator: std.mem.Allocator, output: *std.ArrayList(u8), value: u16) std.mem.Allocator.Error!void {
    try output.appendSlice(allocator, &.{ @intCast(value >> 8), @truncate(value) });
}

fn appendU32(allocator: std.mem.Allocator, output: *std.ArrayList(u8), value: u32) std.mem.Allocator.Error!void {
    try output.appendSlice(allocator, &.{
        @intCast(value >> 24),
        @truncate(value >> 16),
        @truncate(value >> 8),
        @truncate(value),
    });
}

/// Bounds-checked view over untrusted bytes. Centralizing cursor movement makes
/// every primitive read fail closed on truncation instead of slicing blindly.
const Cursor = struct {
    bytes: []const u8,
    index: usize = 0,

    fn take(self: *Cursor, length: usize) DecodeError![]const u8 {
        if (length > self.bytes.len - self.index) return error.Truncated;
        defer self.index += length;
        return self.bytes[self.index..][0..length];
    }

    fn readByte(self: *Cursor) DecodeError!u8 {
        return (try self.take(1))[0];
    }

    fn readU16(self: *Cursor) DecodeError!u16 {
        const bytes = try self.take(2);
        return (@as(u16, bytes[0]) << 8) | bytes[1];
    }

    fn readU32(self: *Cursor) DecodeError!u32 {
        const bytes = try self.take(4);
        return (@as(u32, bytes[0]) << 24) |
            (@as(u32, bytes[1]) << 16) |
            (@as(u32, bytes[2]) << 8) |
            bytes[3];
    }

    fn readI32(self: *Cursor) DecodeError!i32 {
        return @bitCast(try self.readU32());
    }
};

test "ETF round-trips the supported structural subset" {
    const allocator = std.testing.allocator;
    var items = [_]Term{
        .{ .atom = "ok" },
        .{ .integer = -42 },
        .{ .binary = "beam" },
    };
    var input = Term{ .tuple = &items };
    const bytes = try encode(allocator, &input);
    defer allocator.free(bytes);

    var decoded = try decode(allocator, bytes, .{});
    defer decoded.deinit(allocator);
    try std.testing.expect(decoded == .tuple);
    try std.testing.expectEqual(@as(usize, 3), decoded.tuple.len);
    try std.testing.expectEqualStrings("ok", decoded.tuple[0].atom);
    try std.testing.expectEqual(@as(i64, -42), decoded.tuple[1].integer);
    try std.testing.expectEqualStrings("beam", decoded.tuple[2].binary);
}

test "ETF rejects truncation and configured size violations" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.Truncated, decode(allocator, &.{ version, binary_ext, 0, 0, 0, 2, 1 }, .{}));
    try std.testing.expectError(error.LimitExceeded, decode(allocator, &.{ version, binary_ext, 0, 0, 0, 2, 1, 2 }, .{ .max_binary_bytes = 1 }));
}

test "ETF rejects truncated collections before allocation" {
    var failing_allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    const allocator = failing_allocator.allocator();
    try std.testing.expectError(error.Truncated, decode(allocator, &.{ version, large_tuple_ext, 0, 0, 0, 1 }, .{}));
    try std.testing.expectError(error.Truncated, decode(allocator, &.{ version, list_ext, 0, 0, 0, 1, nil_ext }, .{}));
}
