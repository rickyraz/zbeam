const std = @import("std");
const zbeam = @import("zbeam");

pub fn main(init: std.process.Init) !void {
    _ = zbeam;

    var buffer: [1024]u8 = undefined;
    var file_writer: std.Io.File.Writer = .init(.stdout(), init.io, &buffer);
    const writer = &file_writer.interface;

    try writer.writeAll(
        \\zbeam research scaffold
        \\EDP, ETF, EPMD, and the actor runtime are not implemented.
        \\See README.md and docs/implementation-status.md.
        \\
    );
    try writer.flush();
}
