# ADR 0005 — Proposed bounded two-worker wire profile

**Status:** proposed; neither implementation nor wire contract is approved.
**Date:** 2026-10-27. **Baseline:** master `39c1efd` (M1 and local M2a accepted).
**Relation:** additive to ADR 0001 and ADR 0004; does not modify `serve-worker`
or supersede the accepted M1 monitor decisions in ADR 0003.

## Decision requested

Approve the candidate below only after resolving the numbered gates. It exposes
exactly two existing task-owned SHA-256 actors through one authenticated peer at
a time. It is not a general actor system, concurrent-peer server, hard deadline,
production deployment or a change to the existing M1 wire profile. Local M2a
passes no network slices to its tasks and is not yet a wire adapter.

## Candidate observable contract

| Operation | Candidate request | Candidate reply or effect |
|---|---|---|
| Discovery | `REG_SEND` to `zbeam_workers`: `{FromPid, Ref, {discover, Name}}`, Name one of atoms `a`, `b` | `{Ref, {ok, Pid}}` or `{Ref, {error, noproc}}` after actor retirement |
| Hash | `SEND` to discovered Pid: `{FromPid, Ref, {hash, Binary}}` | `{Ref, {ok, Digest}}`, or bounded stopped/failure result if accepted but canceled |
| Stop one | `SEND` to Pid: `{FromPid, Ref, stop}` | retires that actor, joins it, returns `{Ref, ok}` and sends PID-monitor `normal`; sibling and discovery endpoint survive |
| Unknown/stale SEND target | any payload | drop, as in M1; no fabricated reply |
| Monitoring | existing negotiated PID and named MONITOR_P/DEMONITOR_P forms | candidate semantics and proof obligations below |

These exact atoms, names, ordering and stop-error forms are proposals, **not**
existing API. Packets and decoded terms retain M1's 2 MiB frame, 1 MiB binary,
64-element, depth-16 and 4 MiB decoded-allocation limits. Peer PID/reference
node and creation must match the authenticated peer; `REG_SEND` sender must
match the envelope. SEND authenticates a node, not an individual process.
Malformed wire controls and peer mismatch close the connection; recognized bad
commands receive bounded errors where a trusted reply target exists. No replay.

### Identity and lifecycle

Generate two distinct full wire PIDs using the service node name, EPMD creation
and independently randomized id/serial values, retrying equality before any
identity is published. Map fixed local IDs to those PIDs only inside the service;
never reinterpret a local `u64` as a PID. PIDs persist through sequential peer
reconnects while their tasks remain live; retired slots cannot be replaced or
reused until a new service instance. EPMD creation plus randomness is not a
persistent uniqueness guarantee. Failure to start either task publishes neither.

Service states are `starting -> running -> closing -> joined`. Each actor follows
M2a's stop/join lifecycle. EPMD registration loss closes admission and joins
cooperative tasks before storage release; noncooperative tasks require external
process kill. Panic/corruption is process-wide. The process owner remains
responsible for no-replay recovery and externally bounded replacement.

## Shared stream, reservation and liveness

Before **any** unbuffered read (including header, tick or control), atomically
reserve one logical queue position and one outstanding-work ticket in *every*
currently routable destination, plus required output/control capacity. Local
senders, if exposed by the adapter, use the same lifecycle/admission gate. A
snapshot, sum of credits, `Demand` counter alone, or calling existing `trySend`
after reading is insufficient. If any reservation fails, roll all back and
perform zero reads/allocations for that frame. One read reservation may be
outstanding per connection. Release all reservations on tick/control/unknown
route; for a work request transfer only the selected actor's reservation at
queue insertion and release the rest. On partial read, cancellation, decoder
failure or disconnect, release every still-owned reservation exactly once and
fail the connection; never resume a partially consumed stream.

Stop and routing changes must linearize with admission. A destination that
retires after the reader reserves capacity cannot cause a dead reservation to be
reused: specify ownership under the gate and release it before joining or peer
teardown. A control blocked behind zero demand is intentionally unread, including
ticks and demonitor. Head-of-line blocking and possible heartbeat disconnection
are explicit consequences, not fairness or liveness guarantees.

**Implementation gap:** M2a currently reserves only inside `trySend` while
copying; neither a pre-read multi-slot reservation nor a reservation-transfer API
exists. Completion collection in `nextResult` releases its ticket immediately.
An adapter must add tested shared reservation and output ownership rules; a
separate unlocked capacity check or an adapter-private counter cannot enforce
these invariants against local sends.

## Memory, writer and connection epoch

- One connection owner alone mutates its fixed monitor table and serializes all
  writes. Actor tasks produce owned inline results, not writer pointers or
  borrowed frame/peer slices. A bounded collector-to-writer handoff must not
  wait under the lifecycle mutex. Its task and any read/write/deadline task must
  be stopped and joined before their arguments or peer storage are freed.
- M2a permits at most ten outstanding tickets and 10 MiB of copied inputs;
  metadata, allocator/provider resources, caller buffers and task stacks are
  additional. One inbound frame (up to 2 MiB plus header), decoded allocations
  (up to 4 MiB), reply correlation, encoded output and monitor notifications are
  additional. Limits are logical allocations, not physical RSS/zero-copy claims.
- Propose ten fixed request-correlation slots, each storing canonical peer PID,
  bounded reference and local request ID. No packet/decoded-term slices escape.
  Hold a separate reserved output token from admission until the writer has
  completed or explicitly dropped the associated reply, even if `nextResult`
  frees the runtime ticket earlier. Count local completions and locally originated
  requests separately if local send is offered; do not silently steal them.
- Propose a connection table of 64 monitors with canonical peer/service names;
  allocate a bounded, independent control-output reserve large enough for all
  stop-triggered monitor exits and the stop reply. Stop cannot require space in
  a work-output queue that is already full. Bound encoded bytes as well as item
  count; account for the encoder's temporary allocations and active write until
  flush/drop. Exact byte bound and allocation failure behavior are gate G3.
- Give each accepted connection an epoch owned by the service. Correlations and
  pending outputs carry that epoch; a mismatch is dropped, never written to a
  later peer. On disconnect, stop reads, quiesce/join all connection-owned tasks,
  drain/drop old results and notifications and clear monitor/correlation state
  before freeing peer storage. Work already accepted by service-owned actors may
  finish, but old results must be consumed/discarded under bounded capacity before
  a new epoch can begin. No result replay. Whether service survives a connection
  loss without restarting its actors is gate G4, not an established behavior.

## Monitor and stop candidate

A single 64-entry table covers PID and registered-name targets. A matching
monitor is idempotent; conflicting reference reuse is a connection error;
matching demonitor removes it. Unknown/stopped PID or unknown name returns
`noproc`; table exhaustion closes the connection. Node/creation checks and
connection-owned canonical names follow M1. Name `zbeam_workers` denotes the
service discovery endpoint, not either worker; its subscriptions survive an
individual actor stop. No outbound subscriptions or links are introduced.

Proposed normal stop ordering is retire routing, stop/join actor, finalize its
accepted work, emit one correlated stop reply, then at most one `normal` exit per
still-registered PID monitor. Output failure closes the connection and drops
remaining notifications; it never claims delivery or replays on reconnect.
Specify whether prior work replies precede the stop reply and how a concurrent
demonitor is ordered before treating this ordering as an accepted contract.

## Gates before implementation approval

1. **G1 — Wire schema:** approve discovery name, two actor names, error atoms,
   malformed/unknown behavior and stop ordering; validate OTP 25/26/27 encodings.
2. **G2 — Reservations:** define a concrete transactional shared-ledger API,
   including stop/read/local-send races, second-slot rollback, cancellation,
   transfer and whether local sends are exposed at all. Prove no zero-demand read.
3. **G3 — Output:** derive item *and byte* bounds for correlated replies, ticks,
   `noproc`, stop reply and up to 64 exits, including encode failure/partial writes.
   Prove collector progress and control reserve under a blocked writer.
4. **G4 — Connection lifetime:** choose whether disconnect drains surviving
   tasks or stops/recreates the entire service; define task joins, epoch-fence,
   deadlines, loss of pending outputs, EPMD loss and externally owned users.
5. **G5 — Monitor ordering:** define PID/name lifetime and stop/demonitor races,
   including full table, duplicate/reference conflicts, and failure of each write.
6. **G6 — Acceptance:** design deterministic ownership/conservation tests and
   conformance vectors, then actual OTP 25/26/27 in debug/safe, existing M1 and
   guardian/owner regressions. No historical M1 or local M2a result is new wire
   evidence. Every implementation behavior travels with tests/docs and a rollback
   boundary; use reviewable independent work units without unsafe interim exports.

Until G1–G6 are resolved and separately approved, T6 remains disabled. A failed
or canceled process can lose results; exactly-once execution, preemption, replay,
TLS, secret handling, production certification and performance are out of scope.
