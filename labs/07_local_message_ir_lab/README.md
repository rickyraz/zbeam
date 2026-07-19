# Lab 07 — Local Message Representation

**Status:** Planned; depends on an ETF term model and local mailbox prototype.

## Objective

Select a local message representation without conflating ETF avoidance with zero-copy transfer.

## Hypothesis

A typed envelope with explicit copied or owned payload variants can preserve local semantics without requiring ETF re-encoding.

## Experiment

Compare wire ETF, fully decoded terms, partially decoded terms, and typed local envelopes for dispatch cost, allocation, ownership clarity, and conversion complexity.

## Required evidence

Representation diagrams, copy/parse counts, benchmarks, and semantic-equivalence tests.

## Promotion gate

The runtime adopts a local IR only after its wire-boundary conversion is explicit and tested.
