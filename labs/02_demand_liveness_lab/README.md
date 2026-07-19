# Lab 02 — Demand Liveness

**Status:** Planned; depends on Lab 01 and a demand prototype.

## Objective

Separate valid backpressure from a stalled actor that no longer grants demand.

## Hypothesis

Demand can remain zero indefinitely as valid application state, so liveness diagnostics must report inactivity without silently granting credits or changing semantics.

## Experiment

Exercise actors that omit grants, grant late, fail before granting, and perform long CPU work. Measure transport progress, diagnostics, cancellation, and recovery behavior.

## Required evidence

A state-transition trace for each scenario, timeout-policy rationale, and tests proving that diagnostics do not consume or invent demand.

## Promotion gate

No watchdog or recovery policy enters the runtime without a documented distinction between observation and semantic intervention.
