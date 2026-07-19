const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var input_buffer: [4096]u8 = undefined;
    var output_buffer: [4096]u8 = undefined;
    var reader: std.Io.File.Reader = .initStreaming(.stdin(), io, &input_buffer);
    var writer: std.Io.File.Writer = .initStreaming(.stdout(), io, &output_buffer);

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

fn readU32(bytes: *const [4]u8) u32 {
    return (@as(u32, bytes[0]) << 24) |
        (@as(u32, bytes[1]) << 16) |
        (@as(u32, bytes[2]) << 8) |
        bytes[3];
}
