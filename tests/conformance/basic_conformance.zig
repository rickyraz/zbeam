const std = @import("std");
const zbeam = @import("zbeam");

test "conformance suite wiring: protocol module is importable" {
    // This is build wiring only. It makes no wire-conformance claim.
    std.testing.refAllDecls(zbeam.protocol);
}
