# M2c plan: a bounded owner for the two-worker profile

**Status: authorized work plan, not implementation evidence.** The accepted
[M2b profile](two-worker-wire.md) owns two fixed SHA-256 tasks in one native
process. M2c makes that existing profile usable from Elixir without changing
its wire protocol or the M1 owner. It remains a Linux development example, not
a production deployment or a general native actor API.

## Delivered contract

- A supervised owner launches one `serve-workers` child through the existing
  Linux guardian, waits for its own registration, discovers and monitors both
  worker PIDs, and exposes `hash(owner, :a | :b, binary)`.
- Accept at most one request per actor through that API; reject further work
  with `busy` before its payload reaches the owner mailbox. Validate the 1 MiB
  input limit first. This bounds admitted API requests, not arbitrary BEAM
  messages, retained caller binaries, or total VM/process RSS.
- A fixed caller-supplied peer node atom and bounded connection/registration
  cleanup avoid generating new BEAM atoms on each restart. Initial name collisions reject
  startup without deliberately connecting to or killing the existing service.
  The owner requires exclusive use of that name and connection; malicious local
  races are outside the cookie's node-wide trust boundary.
- A controlled retirement or handled failure of `a` marks it unavailable while
  `b` remains usable. Slots are not replaced inside the native process. A
  process/node loss or uncertain timeout fails in-flight work and retires the
  whole owned process; sibling work can consequently fail too.
- Never replay uncertain work. A timeout is not proof that execution did not
  occur. Fresh requests after replacement use fresh native PIDs/references.
- A dead caller, including death between admission and delivery, cannot reopen
  a slot while its old operation might run. Stop admission before disconnecting;
  join/kill only owned children, and never free live native task storage.

## Review units and acceptance

| Order | Work unit | Proof required |
|---|---|---|
| C0 | Contract and rollback boundaries | This plan; no M1/M2b runtime changes. |
| C1 | Pre-mailbox admission primitive | Atomic per-actor slots, payload-size rejection, dead-table and caller/owner races; no public service yet. |
| C2 | Owned launcher, supervised owner and exact hashes | Both PIDs ready before admission, one request per actor, bounded name/registration handling and startup rollback; M1 stays separate. |
| C3 | Actor retirement and failure paths | Monitor identity, independent sibling progress on controlled retirement, timeout/connection loss, two in-flight failures, stale replies and no replay. |
| C4 | Process and caller cleanup | Claim-before-delivery death, owner/guardian/VM loss, restart intensity, name collision and owned-child cleanup. Fault injection remains test-only. |
| C5 | Integration and acceptance | Runnable example, mandatory CI, debug/safe core/labs/lifecycle and M1/M2b regressions; native OTP 25/26/27 in both modes; Elixir 1.17.3 with OTP 25/26/27 in safe mode and Elixir 1.20.4 with OTP 29 in both modes; exact actual-master CI and evidence. |

Each independently reviewed unit includes its own tests and evidence, targets at
most 400 changed text lines, and can be rolled back without losing unrelated
behavior. Do not publish an owner that lacks its cleanup/admission guarantees to
meet the size budget. Missing OTP targets are not passes. Keep failure logs and
record cached or skipped checks separately.

## Explicit exclusions

No arbitrary native handlers, dynamic actor replacement, second peer, replay,
preemption, TLS, or production certification is introduced. M2b's conservative
shared-stream gate can stall sibling traffic and heartbeats under saturation.
A noncooperative handler requires external process kill/reap; panic/corruption is
process-wide. Cookie arguments remain visible. Native-host soak, OS-OOM,
corruption, security review and BEAM-side backpressure measurements remain open.
