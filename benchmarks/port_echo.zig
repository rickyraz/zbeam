const std = @import("std");

/// Reference worker for Erlang Port packet mode. The process does no ETF work:
/// it reads `[u32 length][payload]` and writes the same frame back, isolating
/// basic BEAM-to-OS-process round-trip cost.
pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var input_buffer: [4096]u8 = undefined;
    var output_buffer: [4096]u8 = undefined;
    var reader: std.Io.File.Reader = .initStreaming(.stdin(), io, &input_buffer);
    var writer: std.Io.File.Writer = .initStreaming(.stdout(), io, &output_buffer);

    // Fixed storage makes the 1 MiB ceiling observable and keeps allocation
    // noise out of per-message latency. Four header octets are required by the
    // Port `{packet, 4}` contract, so the length is an unsigned 32-bit value.
    var payload: [1024 * 1024]u8 = undefined;
    while (true) {
        var header: [4]u8 = undefined;
        reader.interface.readSliceAll(&header) catch |err| switch (err) {
            error.EndOfStream => return,
            else => return err,
        };
        const length = readU32(&header);
        if (length > payload.len) return error.PacketTooLarge;
        try reader.interface.readSliceAll(payload[0..length]);
        try writer.interface.writeAll(&header);
        try writer.interface.writeAll(payload[0..length]);
        try writer.interface.flush();
    }
}

/// Decodes Port packet length in network byte order, eight bits per octet.
fn readU32(bytes: *const [4]u8) u32 {
    return (@as(u32, bytes[0]) << 24) |
        (@as(u32, bytes[1]) << 16) |
        (@as(u32, bytes[2]) << 8) |
        bytes[3];
}
