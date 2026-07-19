# Lab 05 — Arena Slot Recycling

**Status:** Planned; deferred until a copied transport path is correct.

## Objective

Prove that arena slots are claimed once, retained while referenced, and recycled exactly once.

## Hypothesis

Atomic claim/release plus a generation-bearing identity prevents duplicate claims, refcount underflow, and stale-handle reuse.

## Experiment

Race more claimers than available slots, retain and release from multiple tasks, force wraparound, attempt double release, and access handles after slot reuse.

## Required evidence

Reference-count traces, slot/generation logs, contention results, and deterministic failure cases for invalid operations.

## Promotion gate

Arena-backed handles remain disabled until slot lifecycle tests pass under stress.
