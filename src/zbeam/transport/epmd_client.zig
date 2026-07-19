const std = @import("std");
const epmd = @import("zbeam-protocol").epmd;

pub const Client = struct {
    io: std.Io,
    address: std.Io.net.IpAddress = .{ .ip4 = .loopback(epmd.default_port) },

    /// Opens the long-lived EPMD registration connection. EPMD removes the
    /// name when this TCP stream closes, so returning the stream is part of the
    /// registration lifetime rather than an implementation detail.
    pub fn register(self: Client, allocator: std.mem.Allocator, options: epmd.AliveOptions) !Registration {
        const request = try epmd.encodeAlive2(allocator, options);
        defer allocator.free(request);

        const stream = try self.address.connect(self.io, .{ .mode = .stream });
        errdefer stream.close(self.io);
        try writeRequest(stream, self.io, request);

        var reader_buffer: [16]u8 = undefined;
        var stream_reader = stream.reader(self.io, &reader_buffer);
        const reader = &stream_reader.interface;
        const tag = try reader.takeByte();
        const response_len: usize = switch (tag) {
            epmd.alive2_resp => 4,
            epmd.alive2_x_resp => 6,
            else => return error.UnexpectedTag,
        };
        var response: [6]u8 = undefined;
        response[0] = tag;
        try reader.readSliceAll(response[1..response_len]);
        const result = try epmd.decodeAliveResponse(response[0..response_len]);
        return .{ .stream = stream, .creation = result.creation };
    }

    /// Resolves a short node name using a short-lived EPMD connection. Reads
    /// fixed fields first, then allocates only after bounded variable lengths
    /// are known; this avoids trusting a remote length up front.
    pub fn lookup(self: Client, allocator: std.mem.Allocator, node_name: []const u8, max_extra: u16) !epmd.NodeInfo {
        const request = try epmd.encodePortPlease2(allocator, node_name);
        defer allocator.free(request);

        const stream = try self.address.connect(self.io, .{ .mode = .stream });
        defer stream.close(self.io);
        try writeRequest(stream, self.io, request);

        var reader_buffer: [512]u8 = undefined;
        var stream_reader = stream.reader(self.io, &reader_buffer);
        const reader = &stream_reader.interface;
        var fixed: [12]u8 = undefined;
        try reader.readSliceAll(&fixed);
        if (fixed[0] != epmd.port2_resp) return error.UnexpectedTag;
        if (fixed[1] != 0) return error.NodeNotFound;
        const name_len = readU16(fixed[10..12]);
        if (name_len > 255) return error.LimitExceeded;
        const prefix_len = fixed.len + @as(usize, name_len) + 2;
        const response = try allocator.alloc(u8, prefix_len + max_extra);
        defer allocator.free(response);
        @memcpy(response[0..fixed.len], &fixed);
        try reader.readSliceAll(response[fixed.len .. fixed.len + name_len + 2]);
        const extra_offset = fixed.len + name_len;
        const extra_len = readU16(response[extra_offset..][0..2]);
        if (extra_len > max_extra) return error.LimitExceeded;
        try reader.readSliceAll(response[prefix_len .. prefix_len + extra_len]);
        return epmd.decodePort2Response(allocator, response[0 .. prefix_len + extra_len], max_extra);
    }
};

pub const Registration = struct {
    stream: std.Io.net.Stream,
    creation: u32,

    /// Closing is semantically "unregister", because EPMD ties liveness to the
    /// connection instead of exposing a separate deregistration request.
    pub fn close(self: *Registration, io: std.Io) void {
        self.stream.close(io);
        self.* = undefined;
    }
};

/// Flushes explicitly because buffered bytes are not visible to EPMD until
/// handed to the socket; waiting for a response before flushing would deadlock.
fn writeRequest(stream: std.Io.net.Stream, io: std.Io, request: []const u8) !void {
    var writer_buffer: [512]u8 = undefined;
    var stream_writer = stream.writer(io, &writer_buffer);
    try stream_writer.interface.writeAll(request);
    try stream_writer.interface.flush();
}

fn readU16(bytes: *const [2]u8) u16 {
    return (@as(u16, bytes[0]) << 8) | bytes[1];
}
