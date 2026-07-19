const std = @import("std");
const transport = @import("zbeam-transport");

// Runs when a local EPMD daemon is available; otherwise reports a skipped test.
test "EPMD registration remains discoverable while its socket is open" {
    const allocator = std.testing.allocator;
    const node_name = try std.fmt.allocPrint(allocator, "zbeam_test_{x}", .{std.testing.random_seed});
    defer allocator.free(node_name);

    const client = transport.epmd_client.Client{ .io = std.testing.io };
    var registration = client.register(allocator, .{
        .port = 34567,
        .node_name = node_name,
    }) catch |err| switch (err) {
        error.ConnectionRefused => return error.SkipZigTest,
        else => return err,
    };
    defer registration.close(std.testing.io);

    var info = try client.lookup(allocator, node_name, 1024);
    defer info.deinit(allocator);
    try std.testing.expectEqual(@as(u16, 34567), info.port);
    try std.testing.expectEqualStrings(node_name, info.node_name);
}
