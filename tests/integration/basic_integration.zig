const std = @import("std");
const zbeam = @import("zbeam");
const etf = @import("zbeam-etf");
const protocol = @import("zbeam-protocol");
const transport = @import("zbeam-transport");
const actor = @import("zbeam-actor");
const runtime = @import("zbeam-runtime");

comptime {
    _ = @import("epmd_integration.zig");
    _ = @import("handshake_integration.zig");
    _ = @import("peer_integration.zig");
}

test "integration: additive task owner works through independent runtime import" {
    const tasks = try runtime.TaskRuntime.create(std.testing.allocator, std.testing.io, .{ "left", "right" });
    defer tasks.deinit() catch unreachable;
    defer _ = tasks.shutdown();
    const id = tasks.whereis("right").?;
    const request = try tasks.trySend(id, "owned work");
    const result = (try tasks.nextResult()).?;
    try std.testing.expectEqual(id, result.actor_id);
    try std.testing.expectEqual(request, result.request_id);
    try std.testing.expect(result.outcome == .digest);
}

test "integration: umbrella and independent battery imports compile" {
    std.testing.refAllDecls(zbeam);
    std.testing.refAllDecls(etf);
    std.testing.refAllDecls(protocol);
    std.testing.refAllDecls(transport);
    std.testing.refAllDecls(actor);
    std.testing.refAllDecls(runtime);
}
