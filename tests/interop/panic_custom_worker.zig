//! Test-only handler fault; never installed into the production executable.
const std = @import("std");
const cli = @import("zbeam-cli");

pub fn main(init: std.process.Init) !void {
    try cli.runCustom(init, panicHandler);
}

fn panicHandler(_: []const u8, _: []u8) error{HandlerFailed}!usize {
    @panic("test-only compiled handler panic");
}
