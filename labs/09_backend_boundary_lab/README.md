# Lab 09 — Backend Boundary

**Status:** Planned; depends on a complete portable transport implementation.

## Objective

Define ownership when `std.Io` and low-level Linux APIs manage the same connection resources.

## Hypothesis

A single owner for descriptors and buffer registration can contain OS-specific behavior without leaking it into protocol or actor modules.

## Experiment

Model descriptor creation, registration, in-flight operations, cancellation, unregister, close, and failure at every transition.

## Required evidence

Resource-lifecycle diagrams, injected-failure tests, and proof that every path releases each resource once.

## Promotion gate

Mixed-backend code requires an ADR naming the owner and cleanup authority for every resource.
