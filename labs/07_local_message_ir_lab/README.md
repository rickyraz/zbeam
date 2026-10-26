# Lab 07 — Local Message Representation

**Status:** Runnable copied-envelope prototype; no production IR decision.

## Objective

Select a local message representation without conflating ETF avoidance with zero-copy transfer.

## Hypothesis

A typed envelope with explicit copied or owned payload variants can preserve local semantics without requiring ETF re-encoding.

## Experiment

Compare wire ETF, fully decoded terms, partially decoded terms, and typed local envelopes for dispatch cost, allocation, ownership clarity, and conversion complexity.

## Required evidence

Representation diagrams, copy/parse counts, benchmarks, and semantic-equivalence tests.

## Runnable subset

Run `zig build lab-07 -j2 --summary all`. The [experiment](experiment.zig)
converts only `{nonnegative_u32_sequence, binary_up_to_32_bytes}`:

```text
ETF bytes -> owned decoded term -> inline copied envelope -> local mailbox
```

The wire buffer and decoded term are released before mailbox delivery. Exact
sequence/payload checks therefore exercise independent envelope storage. Bad
shape, negative/overflowing sequence and over-capacity payloads are rejected;
the exact capacity is accepted.

One wire decode and zero local re-encodes do not imply zero-copy: conversion
copies payload bytes, and mailbox delivery copies the inline value. Output
reports the envelope's storage size on the current target. Partial decoding,
throughput and representation-wide benchmarks remain unmeasured.

## Promotion gate

The runtime adopts a local IR only after its wire-boundary conversion is explicit and tested.
