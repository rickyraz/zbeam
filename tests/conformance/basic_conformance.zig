const std = @import("std");
const etf = @import("zbeam-etf");
const protocol = @import("zbeam-protocol");

comptime {
    _ = @import("fixture_manifest.zig");
}

test "conformance suite wiring: pure wire batteries are importable" {
    // This is build wiring only. It makes no wire-conformance claim.
    std.testing.refAllDecls(etf);
    std.testing.refAllDecls(protocol);
}
