//! Uses both standalone batteries and the umbrella from the fetched archive.
const std = @import("std");
const etf = @import("zbeam-etf");
const actor = @import("zbeam-actor");
const zbeam = @import("zbeam");

pub fn main(init: std.process.Init) !void {
    var items = [_]etf.Term{ .{ .atom = "ok" }, .{ .integer = 42 } };
    const bytes = try etf.encode(init.gpa, &.{ .tuple = &items });
    defer init.gpa.free(bytes);
    var decoded = try etf.decode(init.gpa, bytes, .{});
    defer decoded.deinit(init.gpa);
    if (decoded.tuple[1].integer != 42) return error.RoundTripMismatch;

    var storage: [1]u32 = undefined;
    var mailbox = actor.Mailbox(u32).init(&storage);
    try mailbox.tryDeliver(init.io, 7);
    if (mailbox.tryDeliver(init.io, 8)) |_| return error.UnboundedMailbox else |_| {}

    const tasks = try zbeam.runtime.TaskRuntime.create(init.gpa, init.io, .{ "a", "b" });
    defer tasks.deinit() catch unreachable;
    _ = try tasks.trySend(1, "abc");
    const result = (try tasks.nextResult()).?;
    _ = tasks.shutdown();
    std.debug.print("PASS package consumer: ETF round trip, bounded mailbox, SHA-256 {x}\n", .{result.outcome.digest[0..4]});
}
