const std = @import("std");
const Demand = @import("zbeam-actor").Demand;

const Observation = enum { ready, paused, inactive, failed };

fn observe(demand: *const Demand, idle_ticks: u32, failed: bool) Observation {
    if (failed) return .failed;
    if (demand.load() != 0) return .ready;
    return if (idle_ticks >= 3) .inactive else .paused;
}

test "lab02: observing omitted, late and failed grants never creates credit" {
    const Scenario = enum { omitted_grant, late_grant, handler_failure, long_cpu_work };
    inline for (std.meta.tags(Scenario)) |scenario| {
        var demand = Demand.init(1);
        try std.testing.expect(demand.tryConsume());
        for (0..6) |tick| {
            if (scenario == .late_grant and tick == 4) try demand.grant(1);
            const before = demand.load();
            const failed = scenario == .handler_failure;
            const observation = observe(&demand, @intCast(tick), failed);
            try std.testing.expectEqual(before, demand.load());
            const expected: Observation = if (failed) .failed else if (before > 0) .ready else if (tick >= 3) .inactive else .paused;
            try std.testing.expectEqual(expected, observation);
            std.debug.print("lab02 scenario={s} tick={d} credits={d} observation={s}\n", .{ @tagName(scenario), tick, before, @tagName(observation) });
        }
        if (scenario == .late_grant) try std.testing.expect(demand.tryConsume());
        try std.testing.expect(!demand.tryConsume());
    }
}

test "lab02: inactivity alone cannot distinguish a paused actor from a failed one" {
    var demand = Demand.init(0);
    try std.testing.expectEqual(Observation.inactive, observe(&demand, 100, false));
    try std.testing.expectEqual(Observation.failed, observe(&demand, 100, true));
    try std.testing.expectEqual(@as(u32, 0), demand.load());
}
