const std = @import("std");
const zbeam = @import("zbeam");

test "integration: public module is importable" {
    try std.testing.expect(zbeam.add(20, 22) == 42);
}
