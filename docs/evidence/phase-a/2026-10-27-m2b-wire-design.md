# M2b wire-design baseline — 2026-10-27

**Design only.** Baseline master `39c1efd5ce3ab3bee46a600d4c75b0b358880a7c`;
Zig 0.17.0, Linux x86-64 WSL2. [ADR 0005](../../adr/0005-two-worker-wire-profile.md)
proposes, but does not approve, wire shapes or new task/connection behavior.

## Source inspection

- `runtime/worker.zig`: M1 handles packet and output synchronously; endpoint
  `zbeam_worker` and one PID, fixed 64-slot peer-owned monitor table. Stop reply
  precedes PID `normal` notifications. No decoded packet slices survive.
- `runtime/node.zig`: M1 worker survives sequential peer connections; one demand
  credit before an unbuffered read, synchronous handler/write, restoration after
  output. Transport/deadline cancellation joins before borrowed arguments leave.
- `runtime/task_runtime.zig` and `task_admission.zig`: `trySend` copies and
  reserves one actor under a mutex, `nextResult` frees its ticket on collection.
  No all-route pre-read reservation, epoch, correlation or writer-output token
  exists. Fixed records are five per actor, queue capacity four, input ≤1 MiB.
- `transport/distribution_io.zig`: `readDemandedPacket` rejects buffered readers,
  consumes a credit before header read and treats partial read error as terminal.
  This independent transport module must not gain an actor/runtime dependency.
- ADR 0003: both monitor flags and named/PID semantics are a coupled M1 profile;
  new names or ordering need their own decision and actual OTP verification.

## Baseline execution

```sh
ZIG_LOCAL_CACHE_DIR=.zig-cache/0.17 zig build test-all test-labs test-task-lifecycle -Doptimize=debug -j2 --summary all
ZIG_LOCAL_CACHE_DIR=.zig-cache/0.17-safe zig build test-all test-labs test-task-lifecycle -Doptimize=safe -j2 --summary all
```

Both commands returned zero: **69/69 steps, 119/121 tests passed, two conditional
skips**, each mode. The standalone watchdog separately confirmed a stalled join
and killed/reaped its owned child; the local example checked three exact digests.
Complete baseline outputs are retained alongside this record. No OTP matrix was
run for this design-only change; existing M1 wire evidence is not M2b evidence.

ADR 0005 identifies gates G1–G6 and explicitly blocks implementation until
approval. This record changes no source, fixture, test, example, build, script,
workflow or accepted ADR body. Rollback removes the proposed ADR, this record
and related status/index/spec links without touching implemented behavior.
