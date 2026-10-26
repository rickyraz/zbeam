const ForwardOnly = @import("experiment.zig").ForwardOnly;

test "forward-only has no direct access method" {
    const handle = ForwardOnly{ .inner = .{ .bytes = "data" } };
    _ = handle.access();
}
