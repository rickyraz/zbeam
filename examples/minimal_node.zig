const std = @import("std");
const zbeam = @import("../src/root.zig");

test "example: use zbeam api" {
    try std.testing.expect(zbeam.add(1, 2) == 3);
}
