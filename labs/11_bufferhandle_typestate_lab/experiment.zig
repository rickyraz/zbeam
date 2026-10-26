const std = @import("std");

pub const Borrowed = struct {
    bytes: []const u8,

    pub fn access(self: @This()) []const u8 {
        return self.bytes;
    }
};

pub const ForwardOnly = struct {
    inner: Borrowed,

    pub fn forward(self: @This()) Borrowed {
        return self.inner;
    }
};

const Owned = struct {
    bytes: [4]u8,
    forwarded: bool = false,

    fn forward(self: *@This()) error{AlreadyForwarded}!ForwardOnly {
        if (self.forwarded) return error.AlreadyForwarded;
        self.forwarded = true;
        return .{ .inner = .{ .bytes = &self.bytes } };
    }
};

test "lab11: an omitted access method does not prevent field or alias escape" {
    var owned = Owned{ .bytes = "data".* };
    const borrowed = Borrowed{ .bytes = &owned.bytes };
    const handle = try owned.forward();
    try std.testing.expectEqualStrings("data", handle.forward().access());
    try std.testing.expectError(error.AlreadyForwarded, owned.forward());
    try std.testing.expectEqualStrings("data", handle.inner.access());
    try std.testing.expectEqualStrings("data", borrowed.access());
    std.debug.print("lab11 direct_method=compile_rejected inner_access=allowed prior_alias=allowed\n", .{});
}

test "lab11: value copying duplicates the consumed-state model" {
    var original = Owned{ .bytes = "data".* };
    var copy = original;
    _ = try original.forward();
    _ = try copy.forward();
    try std.testing.expect(original.forwarded and copy.forwarded);
}
