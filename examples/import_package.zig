const std = @import("std");
const zbeam = @import("zbeam");

// Applications may import the umbrella battery or a narrower module such as
// `zbeam-etf` when configured by their build.
test "example: import the umbrella package" {
    std.testing.refAllDecls(zbeam);
}
