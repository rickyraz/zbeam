# Supervised owner for the compiled-handler profile

- **Date:** 2026-11-09 UTC.
- **Base:** master `ebd20e1ee381e5f8ece61d8eefe066ecb02d15e7`.
- **Requirement:** run an [ADR 0006](../../adr/0006-compiled-binary-handler.md) handler through the bounded M2c owner instead of only the raw example client.

## Change

`TwoWorkerOwner` accepts `profile: :sha256` (default) or `profile: :custom`. The
custom profile launches `serve-custom` and exposes `TwoWorkerOwner.call/3`, which
returns `{:ok, binary}` with 0–32 bytes. Admission, `busy`, per-actor stop,
timeouts, caller monitoring, restart and no-replay rules are shared with
`hash/3`. A command from the other profile returns `{:error, :unsupported}` and
releases its admission slot before reaching the native process. An unknown
profile fails startup without launching a child. `examples/custom_client.exs`
now uses this owner; the raw wire remains covered by the existing custom tests.

## Tests

`tests/interop/two_worker_custom_owner_test.exs` runs against the actual
`zbeam-custom-worker` and `zbeam` executables:

1. calls on both actors, including empty and 32-byte output, `hash/3` rejection
   with the slot released, and input/actor validation;
2. `call/3` rejection by a SHA-256 owner, followed by an exact digest;
3. an unknown profile, which does not start or connect a child;
4. a paused native child: one admitted call, `busy` for a second call and for
   stop, then the exact result after resume; an actual 33-byte handler failure
   retires only `a`, and a stop retires only `b`;
5. SIGKILL of the native child with two calls in flight: both callers receive
   `worker_lost`, the replacement has new actor PIDs and an empty pending map,
   and only the fresh call is answered.

## Local results

Linux WSL2 x86-64, Zig 0.17.0, Elixir 1.20.4 / OTP 29.1.1.

- The new suite passed 5/5 in eleven fresh VMs (debug executables).
- The existing owner suite passed 15/15 with the changed owner.
- `zig build test-all test-labs test-task-lifecycle test-worker-recovery
  -Doptimize={debug,safe} -j2 --summary all` passed **77/77 steps and 182/186
  Zig tests** in each mode, with no cached steps in this new worktree. The four
  skips are the two watchdog-gated noncooperative cases, compiled into two test
  binaries; `test-task-lifecycle` runs them through the external watchdog.
- Logs: `~/.local/state/zbeam-maintenance/2026-11-09-m3/custom-owner-*.log`.

The CI `test-worker-recovery` lanes (Elixir 1.17.3 with OTP 25/26/27, and
Elixir 1.20.4 with OTP 29) run the same suite.

## Limits

Outputs remain at most 32 bytes. Admission bounds calls made through the owner,
not arbitrary BEAM messages or total memory. A panic or noncooperative handler
still affects the whole native process. Successful send does not establish
whether uncertain work ran; it is never replayed.

**Rollback:** revert the owner profile option, the example change, the new test
and its script line, and this record together. The SHA-256 owner API is
unchanged by the rollback.
