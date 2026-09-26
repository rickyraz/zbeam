const std = @import("std");
const actor = @import("zbeam-actor");
const runtime = @import("zbeam-runtime");

comptime {
    _ = @import("mailbox_stress.zig");
    _ = @import("backpressure_stress.zig");
}

test "stress suite wiring: actor batteries are importable" {
    std.testing.refAllDecls(actor);
    std.testing.refAllDecls(runtime);
}
