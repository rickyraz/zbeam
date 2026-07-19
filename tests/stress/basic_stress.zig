const std = @import("std");
const actor = @import("zbeam-actor");
const runtime = @import("zbeam-runtime");

comptime {
    _ = @import("mailbox_stress.zig");
}

test "stress suite wiring: actor batteries are importable" {
    // This is build wiring only. Runtime stress cases begin with M2.
    std.testing.refAllDecls(actor);
    std.testing.refAllDecls(runtime);
}
