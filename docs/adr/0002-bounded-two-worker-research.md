# ADR 0002 — Bounded two-worker research

**Status:** experimental contract; not a production scheduler API.
**Date:** 2026-10-13.

## Decision

The local experiment uses two existing `Runtime(Message)` entries and `std.Io` tasks. Each mailbox has four fixed slots with 1024 inline owned bytes per message. Producer and active-handler storage count separately. No packet slice or external allocation escapes into the queue. Mailboxes, registry and contexts stay alive until every send/receive task is joined. Termination removes identity and closes the queue; an already-resolved send may report `Closed`, a later resolution `ActorNotFound`. Neither error authorizes early destruction.

A shared unbuffered connection cannot admit by summing destination credits: the next frame may target a full queue. The conservative research admission rule is the minimum per-destination free capacity. It permits bounded head-of-line blocking. Already-admitted fast work can progress while the other worker pauses; this does not promise that the shared connection remains readable. No speculative transport read or pending-route queue is added.

A two-process control uses separate connections and the same total visible CPU set. It provides OS-process isolation, unlike two mailboxes in one native process. Local mailbox liveness is not a matched throughput comparison to that network topology.

## Limits and verification

The adversarial test fills the paused worker queue, starts a blocked send, verifies independent fast progress, terminates identities and joins every task before storage destruction. Dynamic message sizes, shared-connection actor routing, PID incarnation, monitor/link controls and comparable two-actor throughput require further implementation/evidence. The experiment does not modify the runtime's caller-managed lifetime contract.
