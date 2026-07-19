# Lab 14 — Fan-Out Demand Composition

**Status:** Planned; deferred until single-consumer demand is correct.

## Objective

Define broadcast and partition demand semantics for consumers with different processing rates.

## Hypothesis

Broadcast effective demand is bounded by the slowest required consumer, while partition demand can aggregate available credits subject to fairness.

## Experiment

Use fast, medium, and slow consumers; test broadcast, round-robin partitioning, and weighted partitioning; record starvation, ordering, memory, and delivery counts.

## Required evidence

Formal credit equations, traceable dispatch decisions, fairness metrics, and slow-consumer behavior.

## Promotion gate

Fan-out remains outside the runtime until single-consumer backpressure has black-box evidence.
