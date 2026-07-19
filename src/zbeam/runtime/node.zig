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
    max_messages: usize = 1,
};

/// Composes transport and actor behavior for one deliberately small peer.
///
/// First principles: EPMD already supplied a listening socket; a TCP accept
/// creates one connection; the handshake authenticates it; only then may
/// distribution frames reach the echo behavior. The configured message bound
/// makes benchmark/process lifetime explicit. Ticks maintain liveness and do
/// not count as application work; zero means run until disconnect/cancellation.
pub fn serve(io: std.Io, allocator: std.mem.Allocator, server: *std.Io.net.Server, config: Config) !void {
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

    var handled: usize = 0;
    while (config.max_messages == 0 or handled < config.max_messages) {
        const packet = try transport.distribution_io.readPacket(allocator, &stream_reader.interface, config.max_packet_bytes);
        defer allocator.free(packet);
        const response = try echo.handle(allocator, packet) orelse continue;
        defer allocator.free(response);
        try transport.distribution_io.writePacket(&stream_writer.interface, response);
        if (!isTick(packet)) handled += 1;
    }
}

/// Checks the complete wire representation, not only one byte: a tick is the
/// four-byte zero length prefix and nothing else.
fn isTick(packet: []const u8) bool {
    return packet.len == 4 and std.mem.allEqual(u8, packet, 0);
}
