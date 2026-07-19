# Lab 15 — Buffer Sizing

**Status:** Planned; last in sequence because it requires representative traffic.

## Objective

Select buffer count, buffer size, and copy threshold from workload measurements.

## Hypothesis

Static defaults are useful only as conservative fallbacks; optimal values depend on frame-size distribution, concurrency, and handle lifetime.

## Experiment

Replay captured traffic across buffer counts and sizes, measure occupancy, cache behavior, fallback allocation, stalled reads, memory, and tail latency.

## Required evidence

Input distribution, parameter matrix, raw benchmark data, sensitivity analysis, and documented hardware.

## Promotion gate

Configuration defaults MUST cite the evidence used to select them and MUST NOT be described as universal optima.
