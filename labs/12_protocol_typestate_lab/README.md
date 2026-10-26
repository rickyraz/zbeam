# Lab 12 — Protocol Typestate

**Status:** Runnable typed-order model backed by the existing runtime FSM; no public typed API.

## Objective

Compare a typed handshake API with a conventional runtime state machine.

## Hypothesis

Typestate can prevent invalid local transition calls, but untrusted wire input and reconnect behavior still require runtime validation.

## Experiment

Encode initiating and accepting handshake transitions, create compile-fail invalid transitions, and compare error reporting and API complexity with the runtime FSM.

## Required evidence

Transition table, compile-fail fixtures, wire-error tests, and maintenance-cost assessment.

## Runnable subset

Run `zig build lab-12 -j2 --summary all`. The [experiment](experiment.zig)
evaluates the existing FSM at compile time instead of duplicating its rules.
[Receiving ACK while idle](compile_fail.zig) must fail with the specific typed
transition diagnostic.

| Role | Legal event sequence |
|---|---|
| Initiator | send NAME -> receive STATUS -> receive CHALLENGE -> send REPLY -> receive ACK |
| Acceptor | receive NAME -> send STATUS -> send CHALLENGE -> receive REPLY -> send ACK |

Both typed paths compile. Separate runtime tests reject truncated ACK, wrong
digest and wrong tag before advancing, then accept an authenticated ACK. Types
only encode local ordering: values can be copied or constructed, and an old
value can be reused. No socket action or peer authentication follows merely
from constructing a `connected` type.

Maintenance cost is one small generic adapter over existing enums plus negative
fixtures; it adds no production API. Full handshake wire coverage remains in
the conformance/integration suites. Reconnect typing and linear sessions are
not established.

## Promotion gate

The typed API must preserve protocol observability and cannot replace runtime validation.
