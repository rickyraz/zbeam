# Lab 06 — Local Ownership Transfer

**Status:** Planned; depends on Lab 05.

## Objective

Compare copied delivery, single-owner transfer, and refcounted transfer between local actors.

## Hypothesis

Ownership transfer benefits only sufficiently large payloads with measurable copy cost; small payloads remain simpler and faster when copied.

## Experiment

Measure latency, throughput, allocation count, retained memory, and misuse behavior across payload sizes and actor chains.

## Required evidence

Copy counts, allocator metrics, payload distribution, safety-failure tests, and break-even analysis.

## Promotion gate

No zero-copy API enters the public surface without measured benefit and explicit cancellation/error ownership.
