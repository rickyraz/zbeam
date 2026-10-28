# ADR 0005 — Bounded two-worker wire profile

**Status:** accepted design; implementation and OTP acceptance remain in progress.
**Date:** 2026-10-27; finalized 2026-10-28 under the owner's direction to complete M2b.
**Relation:** additive to ADR 0001 and ADR 0004. It does not change the M1
`serve-worker` profile or supersede ADR 0003.

## Decision

Expose exactly two fixed task-owned SHA-256 actors through one authenticated
Erlang Distribution peer at a time, using a service-owned, private `TaskRuntime`.
The runtime is not shared with local senders or another collector. This is not a
general actor system, concurrent-peer server, hard deadline or production
certification. The service owns one collector and one lifecycle owner; neither
peer data nor frame slices escape to tasks.

| Operation | Request | Reply or effect |
|---|---|---|
| Discovery | `REG_SEND` to `zbeam_workers`: `{FromPid, Ref, {discover, Name}}`, where Name is atom `a` or `b` | `{Ref, {ok, Pid}}`, or `{Ref, {error, noproc}}` for a retired slot |
| Hash | `SEND` to a worker PID: `{FromPid, Ref, {hash, Binary}}` | `{Ref, {ok, Digest}}`, or `{Ref, {error, stopped\|canceled\|handler_failed}}` for accepted work |
| Stop | `SEND` to a worker PID: `{FromPid, Ref, stop}` | retire and join that actor; `{Ref, ok}` then PID monitor `normal` exits; sibling and discovery endpoint survive |
| Unknown/stale SEND target | any payload | drop, no fabricated reply |
| Monitoring | negotiated PID/named `MONITOR_P` and `DEMONITOR_P` | rules below |

Handler failure returns `handler_failed` and PID-monitor exits with that reason.
A stop encountering an already failed handler returns `handler_failed` instead
of `ok`. Wire limits remain M1's 2 MiB frame, 1 MiB binary, 64-element,
depth-16 and 4 MiB decoded-allocation limits. A peer PID/reference node and
creation must match the authenticated peer; REG_SEND sender must equal the
message envelope PID. SEND authenticates a node, not an individual process.
Malformed controls or peer mismatch close the connection; recognized malformed
commands receive `bad_request` only where a trusted reply target exists. No replay.

## Identity and lifecycle

Generate two distinct full wire PIDs from the service node name, EPMD creation
and independent random id/serial values, retrying equality before publication.
Map fixed local IDs to these PIDs only inside the service. Both tasks must start
before either identity is published. PIDs persist across sequential connections
while the actors remain live; retired slots cannot be replaced until a new
service instance. EPMD creation and randomness are not persistent uniqueness.

Service states are `starting -> running -> closing -> joined`. EPMD registration
loss closes admission and joins the service and cooperative tasks before storage
release. A noncooperative task requires external process kill; panic/corruption
is process-wide. An external owner supplies bounded restart and no-replay recovery.

## Demand, output and memory

Before any unbuffered read, including ticks and controls, reserve one logical
queue position and outstanding-work ticket in every currently routable actor,
plus one output credit. Reserve under the common lifecycle gate, roll back all
on failure, and perform zero reads/allocations when any reservation fails. A
single read reservation is outstanding. Release on control, tick, stale route,
error or cancellation; transfer only the selected actor reservation on accepted
work. Stop and admission linearize under the same gate. A stopped actor's held
reservation is retired before join. Reader arguments and frame reservations stay
alive until the reader has actually joined.

The connection owner alone mutates correlation and monitor tables and serializes
writes. Ten fixed correlation credits are held from admission through reply write
or explicit drop, independently of runtime tickets freed by collection. Peer
names are canonicalized into storage that outlives all connection users. No
collector waits while holding the runtime mutex. Output uses one 16 KiB fixed
scratch buffer including encoder temporaries, and one synchronous write at a
time; there is no queued encoded-output backlog. The frame's reserved credit
covers its control reply, and sequentially encoded monitor exits need no array
of 64 output buffers. A blocked writer stops dispatch until its cooperative
write deadline; failure/partial write closes the connection and drops remaining
notifications. It never promises delivery or replay. This sequential design
must be proven under saturation and writer failure before public acceptance.

At most ten runtime work tickets and 10 MiB copied task payloads are live;
metadata, allocator/provider resources and task stacks are additional. One frame
up to 2 MiB plus header, up to 4 MiB decoded allocations, ten correlations, 64
monitor entries and encoding scratch are additional logical limits, not an RSS
or zero-copy guarantee. When demand is zero, even ticks and monitor controls are
unread; head-of-line blocking and possible heartbeat disconnect are intentional.

## Connection epochs and monitoring

An ordinary disconnect does not replace service actors or PIDs. Stop reads,
cancel and join reader/collector/writer operations, release the held frame,
drain and discard every accepted old-epoch completion, then discard monitor
and correlation state before freeing peer storage or accepting a new epoch. An
epoch mismatch is never delivered to a later peer. A noncooperative accepted
job can indefinitely delay drain; cancellation does not preempt CPU work.

One 64-entry connection table covers worker PID and `zbeam_workers` named
subscriptions. Matching duplicate monitors are idempotent; conflicting
reference reuse or table exhaustion closes the connection. Matching demonitor
removes the entry. Unknown or stopped targets get `noproc`. The named endpoint
lives for the service, so a worker stop does not terminate its subscriptions.
Disconnect clears all subscriptions and the peer observes connection loss.

The single dispatcher orders controls as read: a demonitor processed before
stop removes that subscription; one behind stop cannot suppress its already
attempted exit. Stop retires routing and joins the target before the stop reply,
then sends each remaining PID exit at most once. Previously accepted work has a
terminal result after join, but its reply may precede **or follow** the stop
reply/monitor exits; no stronger cross-request ordering is promised. Output
failure closes the connection and does not undo retirement or replay anything.

## Acceptance and exclusions

Before enabling or accepting the service, prove transactional admission,
zero-demand no-read, output bounds, stop/control ordering, epoch cleanup and
fault paths. Independently generated wire vectors and actual OTP 25/26/27 in
both debug and safe modes must accompany the existing M1, local M2a and owner
regression matrix. Tests must distinguish conditional skips, cached work, and
actual external kill/reap. See the [implementation status](../implementation-status.md)
for delivered behavior; this decision is not itself implementation evidence.

Exactly-once execution across process loss, preemption, replay, generic handlers,
TLS/secrets, physical-memory certification and performance claims are excluded.
