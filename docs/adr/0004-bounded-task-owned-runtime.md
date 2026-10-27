# ADR 0004 — Bounded task-owned runtime

**Status:** accepted for local M2a by owner approval on 2026-10-27; implementation pending. M2b remains a separately gated proposal, not an accepted wire contract.
**Date:** 2026-10-27.
**Baseline:** accepted M1, master `cd81a21`.
**Relation:** additive to ADR 0001; does not supersede ADR 0002/0003's M1 profile.

## Context

`runtime/actors.zig` registers caller-owned mailboxes and returns raw mailbox
handles. `sendNamed` resolves under a mutex but delivers after unlocking;
termination removes identity and closes the queue, not the resolved sender's
lifetime. `Mailbox(T)` neither owns nested allocations nor schedules consumers.
Its token is a copyable logical ID, not a task/thread capability. These are valid
low-level contracts, not a foundation for freeing storage immediately on stop.

Zig 0.17 `Io.concurrent` guarantees a concurrency resource or fails with
`ConcurrencyUnavailable`; `Io.async` may execute inline. `Future.cancel` requests
cooperative cancellation **and waits**, is not threadsafe, and is not a bounded
kill primitive. `Group` joins/cancels as a whole, so per-actor Futures fit two
independently stoppable actors. The research queue-close result permits an
already-pending put to succeed; closing is not a sender-quiescence barrier.

## Proposed scope and migration

M2a adds a separately named `TaskRuntime` in the runtime battery; keep existing
`Runtime(T)`, `Mailbox(T)`, exports and all M1 commands compatible. Names below
are contract sketches, not final Zig signatures. Start with two configured
SHA-256 actors, fixed names, no dynamic spawn/replacement or generic handler
plugin API. Pauses, errors and spin remain test-only. General handlers require
a later owned-state/destructor contract, not an unchecked `*anyopaque` escape.

M2b is a separately reviewed wire adapter; M2a alone is not multi-actor OTP
support or completion of full M2. No scheduler backend, work stealing, tracing
GC, arena, zero-copy, links, native supervision, allocator adoption or parallel
peer service is introduced. Protocol/transport retain the ADR 0001 dependency DAG.

## Ownership and bounds

| Resource | Owner / bound / release barrier |
|---|---|
| Runtime object, two slot records, names, mailbox buffers, Futures | Runtime at a stable address until joined and externally quiescent; copy names, max 64 bytes each |
| Actor execution | One `Io.concurrent` Future per slot, managed only by one lifecycle owner; no detached child tasks |
| Mailbox consumer | Runtime's receive loop only; user receives value IDs/results, never mailbox pointers/tokens |
| Payload | Runtime copies borrowed input, at most 1 MiB/request; one allocator provenance and exactly one destruction |
| Mailbox | Four queued requests per actor; one additional active handler per actor |
| Admission | Five outstanding tickets per actor, including reservations, queued, active and completed-uncollected work |
| Completion | Ten fixed records total, containing actor/request ID and inline 32-byte digest or bounded error enum; one collector |
| Identity | Nonzero runtime-scoped IDs; no slot/ID reuse until runtime destruction; stale IDs reject after stop |
| Allocator / I/O provider | Caller supplies capabilities that outlive all tasks; allocator must support concurrent use |

Payload allocations, including a sender's not-yet-enqueued copy, are bounded by
`2 * 5 * 1 MiB = 10 MiB`; metadata, task stacks/provider resources and later wire
buffers are **additional**, not an RSS guarantee. Queue capacity is not the whole
memory bound. A ticket is released only when its terminal completion is collected
or explicitly discarded at deinit. Payload is freed earlier on processing/drop.
This also bounds an absent/slow result consumer without a hidden completion queue.
Caller-owned input and unlimited caller-created threads are outside runtime-owned
memory; the runtime does not create waiting sender tasks or copy on `WouldBlock`.

IDs are meaningful only with the live runtime instance. Handles cannot outlive
that instance; a new runtime is not permission to reuse a stale handle. M2b must
map these IDs to full wire PIDs/incarnation, not reinterpret a local integer as
an ETF PID. No persistent uniqueness or in-process restart claim follows.

## Start, send and stop linearization

`create/start` allocates stable storage before spawning, starts both Futures
behind a readiness barrier, and publishes both actor IDs only after both starts
succeed. A second-task failure stops and joins the first, then releases state;
no half-published service. No fallback from `concurrent` to inline `async`.
Starting, joining and destroying belong to one control owner; actors cannot
self-join or spawn unmanaged tasks through this API.

`trySend(id, borrowed_bytes)` validates size and resolves a running slot under
one lifecycle/admission mutex. It reserves a ticket and one of four logical
queue positions before allocating/copying input, then attempts one-element queue
insertion with `min = 0`; a narrow tested mailbox
operation may expose this existing `Io.Queue` behavior. It never waits for queue
space. Successful insertion is the acceptance/ownership-transfer point and
returns a unique request ID. Full/closed/canceled/OOM failure frees the private
copy and releases the reservation, leaving the caller's input unchanged.
Request-ID exhaustion returns an error before acceptance; no wraparound.

All state/admission updates and queue close are serialized by that mutex.
No blocking queue wait, handler invocation, result wait or Future join occurs
while holding it. The initial bounded copy/allocation remains inside the mutex:
this costs contention but avoids reservation pins/refcounts in a two-slot design.
Workers release queue-internal locks before acquiring the lifecycle mutex; no
reverse lock order. `min = 0` means no capacity wait, not lock-free execution.

`requestStop(id)` changes `running -> stopping`, removes routability and closes
the queue under the same gate. Later sends fail `ActorStopped`; an overlapping
send either committed before stop or returns without transfer. Unlike the old
blocking API, this new path never links pending putters. Existing low-level
mailbox behavior is unchanged, not assumed fixed by this design.

Every successful dequeue transfers cleanup responsibility to the worker,
even before handler entry. Under the gate it releases the logical queue position
and checks stopping before claiming the request as active; otherwise it destroys
that payload and publishes `Stopped`. A request claimed first may complete or
observe cancellation; no new
handler begins after stop wins that ordering. On exit/error, the wrapper retires
identity and publishes a fixed exit outcome. Slots remain allocated even after
name removal and task return. The other actor is not implicitly stopped.

## Shutdown and join

Actor state: `starting -> running -> stopping -> exited -> joined`; startup or
handler failure also retires through `exited`. Runtime: `ready -> running ->
closing -> joined`. Stop/join are idempotent once their outcome is recorded.

1. `shutdown` marks the runtime closing and requests stop for **both** actors
   before waiting on either. Shutdown signals wake cooperative test waits;
   queue close wakes blocked receives. New sends are rejected.
2. The single lifecycle owner invokes `Future.cancel` for stopping tasks (or
   `await` for an already finished task). Both are joins, not fire-and-forget
   signals. Every started task is joined, even if another returned an error.
3. After an actor joins, its former consumer is gone. The owner drains and
   destroys remaining queued payloads, publishing one `Stopped` completion per
   discarded request. Dequeued-request cleanup stays with the worker's defer;
   bounded cleanup cannot be skipped by cancellation and performs no new allocation.
4. On controlled paths in a live runtime, each accepted request has exactly one
   terminal record: digest, handler error or stopped/canceled outcome. A digest produced before cancellation can win;
   stop never promises that previously accepted work had no effect. No replay.
   Tickets reserve completion capacity, so cleanup never blocks on a full result
   queue. Assert conservation; do not silently drop an accounting overflow.
5. Close result production after both joins and drains. `shutdown` returns a
   two-slot exit report, preserving errors without abandoning cleanup. Remaining
   results are readable; deinit explicitly discards uncollected inline records.
6. The caller stops and joins its own send/result/control users **before deinit**.
   Only a joined, externally quiescent runtime may free storage. Otherwise
   deinit refuses (e.g. `NotJoined`); it never silently frees or auto-detaches.

The object itself still needs an external owner. A mutex/counter inside freed
memory cannot make a late API call safe. Concurrent send/stop is supported while
that owner keeps the runtime alive; concurrent deinit/use is not supported.

There is no hard in-process shutdown deadline for arbitrary CPU code. Existing
`transport.deadline.run` also cancels/joins its losing task and cannot safely
preempt a spin. A watchdog may report expired shutdown, but storage stays owned;
an external supervisor must terminate the native process when cooperation fails.
Panic/corruption remains a process fault, not a catchable actor-local exception.

## Wire expansion gate (M2b)

Keep `serve-worker` unchanged. Before adding an explicit two-worker service,
review its discovery/stop/reply schema and re-run OTP 25/26/27 both modes.
Unknown next destinations require **atomic reservations**, not summed credits
or an unlocked minimum snapshot: reserve a queue position and outstanding-work
budget for every routable destination before one unbuffered read. Local senders
must share this ledger. Retain the selected reservation and release the others;
controls/unknown routes release all. Zero effective demand means no read,
including ticks/monitors; bounded head-of-line blocking remains intentional.

One connection owner serializes all writes and monitor-table mutations. Workers
emit owned values, never borrowed packet/peer slices or writer pointers. Count
reader/decoder/copy/output buffers and queued monitor notifications separately;
retain budgets through write completion/drop. Fence completions with a connection
epoch and join/drop old work before peer teardown/reconnect; never replay it.
Define PID retirement/monitor ordering, named-endpoint lifetime and table-full
failure before enabling flags. These wire details are a required follow-up
decision, not implied by acceptance of this local-runtime ADR.

## Consequences and evidence gate

Fixed retained slots and nonblocking admission avoid dynamic reclamation, blocked
send pins and generational slot reuse, at the cost of restarting the runtime to
replace an actor. Bounded copying is deliberately not a throughput optimization.
Future slot reuse/blocking send requires a new lifetime design and evidence.

The [M2 work plan](../m2-task-lifecycle-plan.md) defines executable gates and
rollback units. Current source inspection is [recorded separately](../evidence/phase-a/2026-10-27-m2-design.md).
Existing M1/research tests are inputs, not execution evidence for these proposals.
