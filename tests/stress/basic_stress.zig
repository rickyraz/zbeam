const std = @import("std");
const zbeam = @import("zbeam");

test "stress suite wiring: runtime module is importable" {
    // This is build wiring only. Runtime stress cases begin with M2.
    std.testing.refAllDecls(zbeam.runtime);
}
