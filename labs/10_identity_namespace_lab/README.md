# Lab 10 — Arena Identity Namespace

**Status:** Planned; depends on reconnect and arena prototypes.

## Objective

Determine the minimum identity that prevents collisions and stale references across connections and reuse.

## Hypothesis

`{connection_incarnation, slot_id, generation}` is sufficient for diagnostics and stale-handle detection; a process-global slot identifier alone is not.

## Experiment

Force slot wraparound, reconnect with reused local IDs, transfer handles between actors, and test identity comparisons across incarnations.

## Required evidence

Collision tests, trace examples, memory-cost comparison, and API impact analysis.

## Promotion gate

Identity representation becomes public only after reconnect and transfer requirements are demonstrated.
