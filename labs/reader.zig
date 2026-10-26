//! Unbuffered, counted input for lab framing oracles; no network claims.
const std = @import("std");
const Self = @This();

interface: std.Io.Reader = .{ .vtable = &.{ .stream = stream }, .buffer = &.{}, .seek = 0, .end = 0 },
bytes: []const u8,
chunk: usize = std.math.maxInt(usize),
read_calls: usize = 0,
consumed: usize = 0,

fn stream(reader: *std.Io.Reader, writer: *std.Io.Writer, limit: std.Io.Limit) std.Io.Reader.StreamError!usize {
    const self: *Self = @fieldParentPtr("interface", reader);
    std.debug.assert(self.chunk > 0);
    self.read_calls += 1;
    if (self.bytes.len == 0) return error.EndOfStream;
    const n = try writer.write(self.bytes[0..limit.minInt(@min(self.chunk, self.bytes.len))]);
    self.bytes = self.bytes[n..];
    self.consumed += n;
    return n;
}
