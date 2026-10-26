# Lab 15 — Buffer Sizing

**Status:** Runnable synthetic accounting model; representative traffic and default selection remain open.

## Objective

Select buffer count, buffer size, and copy threshold from workload measurements.

## Hypothesis

Static defaults are useful only as conservative fallbacks; optimal values depend on frame-size distribution, concurrency, and handle lifetime.

## Experiment

Replay captured traffic across buffer counts and sizes, measure occupancy, cache behavior, fallback allocation, stalled reads, memory, and tail latency.

## Required evidence

Input distribution, parameter matrix, raw benchmark data, sensitivity analysis, and documented hardware.

## Runnable subset

Run `zig build lab-15 -j2 --summary all`. The [experiment](experiment.zig)
contains an explicitly synthetic histogram, not captured production traffic:

| Frame bytes | Occurrences |
|---|---|
| 32 | 80 |
| 256 | 15 |
| 4,096 | 4 |
| 65,536 | 1 |

The 3x3 matrix combines 1/4/16 slots with 64/1,024/65,536-byte slots. Reserved
pool bytes are `slots * size`; fit is inclusive at the size boundary. Oversized
payload bytes are reported separately. Cumulative padding sums unused slot
bytes across fitting frames; it is **not** peak memory or live occupancy.
All arithmetic is checked; exact fit, empty input, invalid pools and overflow
have regression tests.

Larger slots fit more of this histogram but reserve more memory and increase
padding. Slot count changes reservation only in this model: no simultaneous
handle lifetimes are simulated. Output cannot choose a default or copy threshold.
Real arrival traces, fallback allocation, occupancy, cache behavior and latency
measurements remain required before that decision.

## Promotion gate

Configuration defaults MUST cite the evidence used to select them and MUST NOT be described as universal optima.
