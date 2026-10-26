const std = @import("std");

const Identity = struct {
    connection: u64,
    slot: u32,
    generation: u8,

    fn validate(self: @This(), live: @This()) error{StaleIdentity}!void {
        if (!std.meta.eql(self, live)) return error.StaleIdentity;
    }
};

fn nextGeneration(current: u8) error{Exhausted}!u8 {
    return std.math.add(u8, current, 1) catch error.Exhausted;
}

test "lab10: reused slots and reconnects reject stale composite identities" {
    var identities: [48]Identity = undefined;
    var count: usize = 0;
    for (1..4) |connection| {
        for (0..4) |slot| {
            for (0..4) |generation| {
                const candidate = Identity{ .connection = connection, .slot = @intCast(slot), .generation = @intCast(generation) };
                for (identities[0..count]) |previous| {
                    try std.testing.expectError(error.StaleIdentity, previous.validate(candidate));
                }
                try candidate.validate(candidate);
                identities[count] = candidate;
                count += 1;
            }
        }
    }
    try std.testing.expectEqual(identities[0].slot, identities[16].slot);
    try std.testing.expectError(error.StaleIdentity, identities[0].validate(identities[16]));
    std.debug.print("lab10 identities={d} distinct_pairs=1128 slot_bytes={d} composite_bytes={d}\n", .{ count, @sizeOf(u32), @sizeOf(Identity) });
}

test "lab10: finite generations must exhaust rather than silently wrap" {
    var generation: u8 = 0;
    for (1..256) |expected| {
        generation = try nextGeneration(generation);
        try std.testing.expectEqual(@as(u8, @intCast(expected)), generation);
    }
    try std.testing.expectError(error.Exhausted, nextGeneration(generation));
    try std.testing.expectEqual(@as(u8, 255), generation);
}
