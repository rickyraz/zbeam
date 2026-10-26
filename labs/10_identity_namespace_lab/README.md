# Lab 10 — Arena Identity Namespace

**Status:** Runnable finite identity model; no arena or public identity API.

## Objective

Determine the minimum identity that prevents collisions and stale references across connections and reuse.

## Hypothesis

`{connection_incarnation, slot_id, generation}` is sufficient for diagnostics and stale-handle detection; a process-global slot identifier alone is not.

## Experiment

Force slot wraparound, reconnect with reused local IDs, transfer handles between actors, and test identity comparisons across incarnations.

## Required evidence

Collision tests, trace examples, memory-cost comparison, and API impact analysis.

## Runnable subset

Run `zig build lab-10 -j2 --summary all`. The [experiment](experiment.zig)
checks all 1,128 distinct pairs in a 48-identity space (3 connections, 4 slots,
4 generations). Reusing a slot across generations or connection incarnations
must fail validation; exact identity must succeed. Output compares slot-only
storage with composite storage including target-specific padding.

An eight-bit generation deliberately reaches exhaustion quickly. All 255
increments succeed, then the next increment rejects instead of wrapping. The
model assumes connection incarnations are unique over live-handle lifetimes;
reusing the entire tuple still collides. Identity comparison alone neither
retains memory nor synchronizes slot reuse. Concurrent reclamation, process
restart identity and production-sized counters remain open design work.

## Promotion gate

Identity representation becomes public only after reconnect and transfer requirements are demonstrated.
