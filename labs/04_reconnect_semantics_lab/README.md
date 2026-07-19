# Lab 04 — Reconnect Semantics

**Status:** Planned; requires handshake, fragmentation, and demand implementations.

## Objective

Define connection incarnation boundaries and state cleanup after disconnect.

## Hypothesis

A reconnect creates a new connection incarnation: partial frames and atom-cache state are discarded, while actor state is retained only where explicitly independent of the old connection.

## Experiment

Interrupt idle traffic, active traffic, and fragmented messages; reconnect with the same node name and a new creation value; inspect fragment, demand, mailbox, monitor, and handle state.

## Required evidence

Before/after state tables, wire traces, cleanup assertions, and bounded reconnect timing.

## Promotion gate

Reconnect behavior becomes normative only after OTP-visible results match the documented contract.
