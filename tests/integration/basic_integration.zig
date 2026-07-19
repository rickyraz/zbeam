const std = @import("std");
const zbeam = @import("zbeam");

test "integration: public package declarations are importable" {
    std.testing.refAllDecls(zbeam);
}
