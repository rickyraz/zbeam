# Lab 14 — Fan-Out Demand Composition

**Status:** Runnable sequential credit model; no runtime fan-out implementation.

## Objective

Define broadcast and partition demand semantics for consumers with different processing rates.

## Hypothesis

Broadcast effective demand is bounded by the slowest required consumer, while partition demand can aggregate available credits subject to fairness.

## Experiment

Use fast, medium, and slow consumers; test broadcast, round-robin partitioning, and weighted partitioning; record starvation, ordering, memory, and delivery counts.

## Required evidence

Formal credit equations, traceable dispatch decisions, fairness metrics, and slow-consumer behavior.

## Runnable subset

Run `zig build lab-14 -j2 --summary all`. The [experiment](experiment.zig)
uses these distinct contracts:

- Broadcast: `effective = min(credits)` over required consumers; one dispatch
  spends one credit from each. An empty set authorizes no dispatch.
- Selectable partition: capacity can sum across consumers only when the
  dispatcher selects a destination with positive credit. Round-robin skips zero.
- Fixed, unknown next destination on a shared connection: a positive sum does
  not authorize a read that might target a full consumer.

Broadcast `[2,1,0]` spends nothing until the last consumer grants. Partition
`[4,4,4]` delivers four each in strict round-robin; `[4,1,0]` delivers four and
one without visiting the paused consumer. Tests assert exact routing, exhaustion
and empty-set behavior.

This is a single-threaded reservation model, not an atomic multi-mailbox commit.
Fairness is established only for the finite balanced schedule, not arbitrary
arrivals. Weighted partitioning, failure rollback, payload ownership and network
fan-out remain deferred; zero-copy broadcast is not implemented.

## Promotion gate

Fan-out remains outside the runtime until single-consumer backpressure has black-box evidence.
