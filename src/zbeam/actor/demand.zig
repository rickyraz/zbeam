const std = @import("std");

/// Thread-safe receive credits: one credit authorizes one future message.
/// `u32` gives a fixed, cheap atomic counter and explicit overflow behavior;
/// demand is a bounded control signal, not an unbounded message count.
pub const Demand = struct {
    available: std.atomic.Value(u32),

    /// Seeds the exact number of credits available before any actor progress.
    pub fn init(initial: u32) Demand {
        return .{ .available = .init(initial) };
    }

    /// Acquire observes credits published by a releasing grant/consume update.
    pub fn load(self: *const Demand) u32 {
        return self.available.load(.acquire);
    }

    /// Adds credits with a compare/exchange loop because multiple grantors may
    /// race. Checked addition rejects wraparound, which would fabricate low
    /// demand from a full counter.
    pub fn grant(self: *Demand, count: u32) error{Overflow}!void {
        var current = self.available.load(.acquire);
        while (true) {
            const next = std.math.add(u32, current, count) catch return error.Overflow;
            if (self.available.cmpxchgWeak(current, next, .acq_rel, .acquire)) |actual| {
                current = actual;
                continue;
            }
            return;
        }
    }

    /// Atomically spends one credit without blocking. A weak CAS may fail
    /// spuriously, so the loop retries using the value actually observed.
    pub fn tryConsume(self: *Demand) bool {
        var current = self.available.load(.acquire);
        while (current > 0) {
            if (self.available.cmpxchgWeak(current, current - 1, .acq_rel, .acquire)) |actual| {
                current = actual;
                continue;
            }
            return true;
        }
        return false;
    }
};

test "demand grants exact credits and detects overflow" {
    var demand = Demand.init(0);
    try demand.grant(2);
    try std.testing.expect(demand.tryConsume());
    try std.testing.expect(demand.tryConsume());
    try std.testing.expect(!demand.tryConsume());

    var full = Demand.init(std.math.maxInt(u32));
    try std.testing.expectError(error.Overflow, full.grant(1));
}
