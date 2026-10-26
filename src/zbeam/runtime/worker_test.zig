const std = @import("std");
const etf = @import("zbeam-etf");
const dist = @import("zbeam-protocol").distribution;
const transport = @import("zbeam-transport");
const worker = @import("worker.zig");

pub const native = etf.Pid{ .node = "worker@host", .creation = 7, .id = 123, .serial = 456 };
pub const sender = etf.Pid{ .node = "client@host", .creation = 8, .id = 1, .serial = 0 };
pub const reference = etf.Reference{ .node = sender.node, .creation = sender.creation, .len = 3, .ids = .{ 1, 2, 3, 0, 0 } };
pub const peer = transport.handshake_io.Peer{ .node_name = sender.node, .creation = sender.creation, .flags = 0 };

pub fn request(allocator: std.mem.Allocator, destination: ?etf.Pid, command: etf.Term) ![]u8 {
    var control = [_]etf.Term{ .{ .integer = dist.reg_send }, .{ .pid = sender }, .{ .atom = "" }, .{ .atom = "zbeam_worker" } };
    if (destination) |pid| {
        control[0] = .{ .integer = dist.send };
        control[1] = .{ .atom = "" };
        control[2] = .{ .pid = pid };
    }
    var fields = [_]etf.Term{ .{ .pid = sender }, .{ .reference = reference }, command };
    return dist.encodePacket(allocator, &.{ .tuple = control[0..if (destination != null) @as(usize, 3) else 4] }, &.{ .tuple = &fields });
}

fn handle(allocator: std.mem.Allocator, destination: ?etf.Pid, command: etf.Term) !void {
    var state = worker.Worker{ .pid = native };
    try state.start();
    const bytes = try request(allocator, destination, command);
    defer allocator.free(bytes);
    var storage: [4096]u8 = undefined;
    var output = std.Io.Writer.fixed(&storage);
    try state.handle(allocator, bytes, &peer, &output);
    var packet = try dist.decodePacket(allocator, output.buffered(), .{});
    defer packet.deinit(allocator);
    var result = try packet.message.decodePayload(allocator, .{});
    defer result.deinit(allocator);
    try std.testing.expect(reference.eql(result.tuple[0].reference));
    if (destination == null) {
        try std.testing.expect(native.eql(result.tuple[1].tuple[1].pid));
    } else if (command == .atom) {
        try std.testing.expectEqualStrings("ok", result.tuple[1].atom);
        try std.testing.expectEqual(worker.State.stopped, state.state);
    } else {
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash("abc", &digest, .{});
        try std.testing.expectEqualSlices(u8, &digest, result.tuple[1].tuple[1].binary);
    }
}

test "worker discovery, exact hash, stop and allocation failures" {
    try handle(std.testing.allocator, null, .{ .atom = "discover" });
    try std.testing.checkAllAllocationFailures(std.testing.allocator, handle, .{ null, etf.Term{ .atom = "discover" } });
    var hash = [_]etf.Term{ .{ .atom = "hash" }, .{ .binary = "abc" } };
    try handle(std.testing.allocator, native, .{ .tuple = &hash });
    try std.testing.checkAllAllocationFailures(std.testing.allocator, handle, .{ @as(?etf.Pid, native), etf.Term{ .tuple = &hash } });
    try handle(std.testing.allocator, native, .{ .atom = "stop" });
    try std.testing.checkAllAllocationFailures(std.testing.allocator, handle, .{ @as(?etf.Pid, native), etf.Term{ .atom = "stop" } });
}

test "worker rejects stale identity and foreign reply origin without changing lifecycle" {
    var state = worker.Worker{ .pid = native };
    try state.start();
    try std.testing.expectError(error.InvalidTransition, state.start());
    var old = native;
    old.serial += 1;
    const bytes = try request(std.testing.allocator, old, .{ .atom = "stop" });
    defer std.testing.allocator.free(bytes);
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try state.handle(std.testing.allocator, bytes, &peer, &output.writer);
    try std.testing.expectEqual(@as(usize, 0), output.written().len);
    try std.testing.expectEqual(worker.State.running, state.state);
    const discovery = try request(std.testing.allocator, null, .{ .atom = "discover" });
    defer std.testing.allocator.free(discovery);
    var other = peer;
    other.creation += 1;
    try std.testing.expectError(error.UnexpectedPeer, state.handle(std.testing.allocator, discovery, &other, &output.writer));
}
