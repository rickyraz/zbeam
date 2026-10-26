# Lab 02 — Demand Liveness

**Status:** Runnable observation model using production `Demand`; no runtime watchdog.

## Objective

Separate valid backpressure from a stalled actor that no longer grants demand.

## Hypothesis

Demand can remain zero indefinitely as valid application state, so liveness diagnostics must report inactivity without silently granting credits or changing semantics.

## Experiment

Exercise actors that omit grants, grant late, fail before granting, and perform long CPU work. Measure transport progress, diagnostics, cancellation, and recovery behavior.

## Required evidence

A state-transition trace for each scenario, timeout-policy rationale, and tests proving that diagnostics do not consume or invent demand.

## Runnable subset

Run `zig build lab-02 -j2 --summary all`. The [experiment](experiment.zig) emits
24 observations for omitted grants, a late grant, explicitly reported failure,
and long work. Logical ticks are deterministic inputs, not elapsed time. The
three-tick inactivity threshold is a test parameter, not a timeout recommendation.

Every observation preserves the exact credit count. Only the explicit late grant
restores progress. Omitted grants and long work deliberately have identical
observations: inactivity cannot identify failure without another signal. Long
CPU work is modeled, not executed or preempted. Cancellation and runtime recovery
remain outside this experiment.

## Promotion gate

No watchdog or recovery policy enters the runtime without a documented distinction between observation and semantic intervention.
