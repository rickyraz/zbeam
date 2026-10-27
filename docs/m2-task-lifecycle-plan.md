# M2 plan: own tasks before expanding wire concurrency

**Status: local M2a implemented and accepted, 2026-10-27; M2b unstarted and gated.** Original design base:
master `cd81a21`, accepted bounded M1. Review
[ADR 0004](adr/0004-bounded-task-owned-runtime.md) first. This plan adds no runtime
API by itself; delivered code is recorded in [M2a acceptance](evidence/phase-c/2026-10-27-m2a-acceptance.md).
Existing `spawn` behavior and all independent research branches remain unchanged.

## Deliverables and acceptance boundaries

| Stage | Deliverable | Not implied |
|---|---|---|
| M2a | Local runtime owning two configured SHA-256 actor tasks, mailbox storage, input copies, completion budgets and stop/join cleanup | Dynamic actors, generic callbacks, multi-actor OTP routing or completion of full M2 |
| M2b | Separately reviewed two-worker wire profile, owned reply routing, monitor ordering and conservative shared-stream admission | Concurrent peers, links, supervision trees, heartbeat-prefetch or production certification |

M2a uses two non-reused slots, four queued requests and one active handler per
actor, inputs up to 1 MiB and five outstanding tickets per actor. Ten completion
records hold inline digests/errors. Result collection returns admission capacity;
no caller means finite backpressure, not growing replies. Stop removes routing,
joins tasks and destroys queued payloads before deinit can release the runtime.
A canceled/noncooperative task does not authorize early free.

## Reviewable work units

T0–T4 are executed through PR #6–#12, with actual-master acceptance at `221a48d`.
T5 has a [proposed wire-profile ADR](adr/0005-two-worker-wire-profile.md); its
numbered gates remain open. T6 has not started. The table preserves review and
rollback boundaries.

Each row is an intended independently reviewable change with tests/docs/evidence,
not a promise that an entire stage fits one PR. Target <=400 added+removed lines;
slice once by coherent behavior if needed, otherwise request a new size exception.
PR #3's exception does not apply. Use ordinary merges; no published-history rewrite.

| Order | Scope / likely files | Required proof / rollback boundary |
|---|---|---|
| T0 — approve design | ADR 0004, this plan, status/risk/spec links | Source/stdlib audit; approve M2a separately from unresolved M2b schema; no code to roll back |
| T1 — owned admission | New `runtime/task_runtime.zig`, owned request/result tests; optional narrow `actor/mailbox.zig` nonblocking insertion | Atomic queue-position/ticket reservation, deep copy, full/OOM/invalid failures and exact destruction; no exported task API until T2; remove new internal module independently |
| T2 — task owner | Startup/readiness wrapper, per-slot Future, runtime export and integration import test | Second-start failure joins first; real concurrency or explicit error, no half-publication, no mailbox/token escape; remove additive export without changing old Runtime |
| T3 — stop/join | Lifecycle implementation and deterministic stress tests | Send/stop linearization, cancellation, idle/full queues, both tasks joined after errors, completion conservation, deinit refusal; T2 must already provide safe basic teardown, never publish an unsafe interim API |
| T4 — M2a acceptance | Two-actor example, regression/evidence/status | Independent admitted progress, slow result collector, exact bounds and no live task after shutdown; accept only M2a, keep M1 unchanged |
| T5 — M2b contract | New wire-profile ADR; accepted ADR 0004 body remains immutable | Discovery, per-actor stop versus node shutdown, PID/name monitor ordering, epoch fence, all memory bounds and control-output reserve decided before implementation |
| T6 — wire adapter | Separate runtime adapter, CLI/profile, protocol tests/fixtures only if changed | Demand reservations shared with local senders; one writer; stale completion rejection; all existing M1 and new OTP/owner gates on the integrated tree |

Implementation may combine inseparable T1/T2 safety pieces into a reviewed unit,
not split ownership from cleanup to meet a line target. No placeholder exports or
untested destructors. New API names remain tentative until T1/T2 signatures and
error contracts compile against Zig 0.17.0.

## Deterministic acceptance matrix

Tests use events/barriers to choose interleavings; timeout is a failure bound,
not a sleep used as proof. Run normal allocator and counted/failing-allocation
variants; account for setup/provider allocations separately from request storage.

| Case | Required observable result |
|---|---|
| Task two cannot start | ConcurrencyUnavailable is visible; task one joined, zero published IDs or retained payloads |
| Input copy / OOM / oversize | Mutating caller buffer cannot change accepted work; each failure preserves caller ownership and restores both reservations |
| Empty, full, direct-to-waiter queue paths | At most four reserved/queued and one active per actor; no linked blocking sender; capacity reused only at the specified transition |
| Send committed before stop | Exactly one completion (digest or stopped/error), one destruction; success is admission, not execution guarantee |
| Stop wins before send/handler claim | New send rejects; dequeued-but-unclaimed message is dropped safely, no handler entry |
| Idle receive and paused handler shutdown | Both wake/observe stop or cancellation and join; no new handler starts, no task touches deinitialized state |
| Handler error / completion racing stop | Actor retires, sibling still progresses; preserve real exit outcome and exactly one terminal record per accepted request |
| Full completion queue / absent collector | Ten tickets/records maximum; WouldBlock without retained input allocation; shutdown never waits on result consumption |
| Repeated stop/join, premature deinit | Idempotent outcome; deinit refuses before join; caller joins its API users before actual destruction |
| Slow actor A; independent B | B completes 100 admitted requests while A is held at a cooperative barrier; local progress only, no shared-wire fairness claim |
| Noncooperative spin | Test-owned subprocess watchdog detects stalled join and kills/reaps it; no fake shutdown success or freed-live storage |
| M2b zero credit, unknown destination, local-send race | No read/allocation until all required destination reservations succeed atomically; no summed-credit shortcut or hidden route buffer |
| M2b disconnect/reconnect and stop/monitor race | Old-epoch results never reach new peers; join/drop before peer free; actual OTP verifies PID/reference/reason and no duplicates |

Conservation oracle on controlled paths at quiescence: accepted requests =
delivered + retained + explicitly discarded terminal results; every accepted
payload is destroyed once, rejected copies never enter the queue, all reservations
return on failure. After deinit: zero retained payloads/results and no task still
accessing runtime state. Process kill/panic may lose results; external callers
must fail uncertain work, never infer replay or exactly-once execution.

## Verification and documentation

- T1–T4: `zig build test-all test-labs -j2 --summary all` in `debug` and `safe`,
  plus focused repeated lifetime tests and exact independent battery imports.
- T4/T6 integrated candidates: native OTP 25/26/27 in both modes; all fourteen
  existing complementary M1 owner cases per mode and standalone guardian. Add
  M2 cases rather than relabeling M1 evidence as new behavior.
- T6: conformance vectors/real OTP for every changed wire shape, overload/partial
  read/write cancellation and reconnect ownership. Missing target blocks acceptance.
- Record commands, actual source SHA, optimizer, Zig/OTP/Elixir/OS, peak live
  request counts/bytes, per-request finalization, failures and repeat count in
  Phase A/B/C as appropriate. Never infer physical RSS or a performance winner
  from logical allocator counts or a short correctness campaign.
- Update implementation status only for executed behavior; synchronize spec,
  risks and runtime exports in the same work unit. Accepted ADR bodies stay immutable.

## Open decisions and exclusions

Owner approval closes T0 for fixed slots/no replacement, nonblocking copy
admission, completion-held tickets and stop-discard semantics. Implementation
uses successive independently verified work-unit PRs to master; no new size
exception or M2b authorization is implied. M2b still needs its wire
schema, control-output capacity proof and disconnect-versus-service lifetime
choice. Until those are settled, keep it disabled and do not widen M1 flags.

No blocking-send API, slot reuse/generation scheme, arbitrary state/destructors,
OS-thread identity tokens, automatic actor restart, scheduler work stealing,
allocator promotion or performance benchmark campaign is needed for M2a.
Caller/provider lifetime and cooperative cancellation remain explicit contracts;
Zig does not statically enforce affine handles or prevent arbitrary slice escape.
