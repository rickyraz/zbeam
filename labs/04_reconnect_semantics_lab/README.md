# Lab 04 — Reconnect Semantics

**Status:** Runnable per-connection cleanup experiment; expanded reconnect semantics remain open.

## Objective

Define connection incarnation boundaries and state cleanup after disconnect.

## Hypothesis

A reconnect creates a new connection incarnation: partial frames and atom-cache state are discarded, while actor state is retained only where explicitly independent of the old connection.

## Experiment

Interrupt idle traffic, active traffic, and fragmented messages; reconnect with the same node name and a new creation value; inspect fragment, demand, mailbox, monitor, and handle state.

## Required evidence

Before/after state tables, wire traces, cleanup assertions, and bounded reconnect timing.

## Runnable subset

Run `zig build lab-04 -j2 --summary all`. The [experiment](experiment.zig) cuts
a seven-byte frame at every incomplete boundary. EOF or truncation spends the
old credit, frees any packet allocation, and cannot authorize another read.
A separately initialized reader and credit then decode the complete frame.

| State | Interrupted connection | Fresh test connection |
|---|---|---|
| Demand | 0 after attempted read | Initialized to 1, spent by one frame |
| Packet allocation | Fully freed on error | Owned until the caller frees it |
| Reader | Discarded; not resumed | New input, no old partial bytes |

The harness explicitly creates fresh state; it does not prove the node creates
it automatically. Existing loopback reconnect checks live in
[`peer_integration.zig`](../../tests/integration/peer_integration.zig), run by
`zig build test-integration`. Creation changes, stale PIDs, replay/backoff and
unsupported fragment/cache state remain outside this subset.

## Promotion gate

Reconnect behavior becomes normative only after OTP-visible results match the documented contract.
