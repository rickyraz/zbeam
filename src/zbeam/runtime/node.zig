const std = @import("std");
const protocol = @import("zbeam-protocol");
const transport = @import("zbeam-transport");
const Echo = @import("echo.zig").Echo;

pub const Config = struct {
    node_name: []const u8,
    cookie: []const u8,
    creation: u32,
    challenge: u32,
    registered_name: []const u8 = "echo",
    flags: u64 = protocol.flags.m1,
    max_packet_bytes: u32 = 16 * 1024 * 1024,
};

/// Accepts one peer, completes the distribution handshake, and serves one
/// registered echo message (ticks do not consume the message allowance).
pub fn serveOne(io: std.Io, allocator: std.mem.Allocator, server: *std.Io.net.Server, config: Config) !void {
    const stream = try server.accept(io);
    defer stream.close(io);
    var peer = try transport.handshake_io.accept(stream, io, allocator, .{
        .node_name = config.node_name,
        .cookie = config.cookie,
        .flags = config.flags,
        .creation = config.creation,
        .challenge = config.challenge,
    });
    defer peer.deinit(allocator);

    var reader_buffer: [8192]u8 = undefined;
    var writer_buffer: [8192]u8 = undefined;
    var stream_reader = stream.reader(io, &reader_buffer);
    var stream_writer = stream.writer(io, &writer_buffer);
    const echo = Echo{ .registered_name = config.registered_name };

    while (true) {
        const packet = try transport.distribution_io.readPacket(allocator, &stream_reader.interface, config.max_packet_bytes);
        defer allocator.free(packet);
        const response = try echo.handle(allocator, packet) orelse continue;
        defer allocator.free(response);
        try transport.distribution_io.writePacket(&stream_writer.interface, response);
        if (!isTick(packet)) return;
    }
}

fn isTick(packet: []const u8) bool {
    return packet.len == 4 and std.mem.allEqual(u8, packet, 0);
}
