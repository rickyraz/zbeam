# Benchmarks

**Status:** No benchmark currently produces publishable performance evidence.

## Suites

- `transport/` — socket, framing, buffering, copy, and cancellation costs.
- `mailbox/` — delivery throughput, contention, wakeups, and tail latency.
- `memory/` — allocation, copying, arena occupancy, and handle lifetime.

## Result requirements

Every published result MUST include the commit, Zig/OTP/kernel versions, target and optimization mode, hardware, command, workload, warmup, sample count, raw output, and summary method.

Comparisons MUST use equivalent semantics and payloads. A faster incomplete protocol path is not a valid comparison. Results belong under a dated evidence directory or attached release artifact; this directory stores benchmark source, not hand-edited headline numbers.

No `bench` build step is registered until the first benchmark executable and result schema exist.
