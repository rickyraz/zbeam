# Lab 13 — Demand Runtime Policy

**Status:** Planned; depends on mailbox and scheduler prototypes.

## Objective

Compare grant-one, batch-credit, and eager-prefetch actor policies.

## Hypothesis

No single demand policy dominates: grant-one bounds memory, while batching improves throughput for workloads that tolerate queued work.

## Experiment

Run latency-sensitive, throughput-oriented, bursty, and mixed actors under each policy; measure throughput, p99 latency, memory, and runnable wait time.

## Required evidence

Workload definitions, scheduler metrics, fairness results, and policy-selection guidance.

## Promotion gate

Defaults require workload evidence and remain configurable only where a real trade-off is demonstrated.
