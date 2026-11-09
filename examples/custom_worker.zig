//! Example stateless handler compiled into a separate executable.
const std = @import("std");
const cli = @import("zbeam-cli");

pub fn main(init: std.process.Init) !void {
    try cli.runCustom(init, uppercase);
}

fn uppercase(input: []const u8, output: []u8) error{HandlerFailed}!usize {
    if (input.len > output.len) return error.HandlerFailed;
    for (input, 0..) |byte, i| output[i] = std.ascii.toUpper(byte);
    return input.len;
}

test "uppercase returns exact bytes and rejects an oversized result" {
    var output: [64]u8 = @splat(0);
    try std.testing.expectEqual(@as(usize, 3), try uppercase("aZ!", &output));
    try std.testing.expectEqualStrings("AZ!", output[0..3]);
    const input: [65]u8 = @splat('a');
    try std.testing.expectError(error.HandlerFailed, uppercase(&input, &output));
}
