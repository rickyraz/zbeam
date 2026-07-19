const std = @import("std");
const zbeam = @import("../src/root.zig");

test "example: import the package surface" {
    std.testing.refAllDecls(zbeam);
}
