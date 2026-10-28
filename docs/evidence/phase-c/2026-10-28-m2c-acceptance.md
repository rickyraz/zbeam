# M2c bounded Elixir owner acceptance — 2026-10-28 UTC

## Accepted boundary

The Linux [two-worker Elixir owner](../../two-worker-wire.md#supervised-elixir-owner)
starts one guarded `serve-workers` process, discovers and monitors both PIDs,
and admits at most one API call per actor before its mailbox. Inputs are limited
to 1 MiB; excess concurrent calls return `busy`. A controlled retirement leaves
the sibling usable. Owner, caller, connection or native loss and uncertain timeout
can fail both pending calls and trigger external supervisor replacement. Old
work is not replayed, and a fresh PID/reference is used for new work. The owner
exposes hash, not a stop API. M1, M2a and the M2b wire contract remain separate.

This bounds admitted API calls, not arbitrary BEAM messages, caller-held binaries
or total RSS. It requires exclusive use of its peer name and connection, Linux
procfs/guardian semantics and trusted local processes. Cookies are visible in
arguments; there is no TLS, exactly-once guarantee, actor-local memory-corruption
isolation or general actor scheduler. Failure/restart may affect both workers.

## Implementation-master verification

- Ordinary PRs #36–#47 produced implementation master
  `f8f0090f045c0f1886f036bff840cb7a5df78bdb`; their candidate heads and merge
  commits are retained in the [PR ledger](2026-10-28-m2c-acceptance/prs.tsv).
  [Actual push CI 40693887236](https://github.com/rickyraz/zbeam/actions/runs/40693887236)
  passed **12/12** jobs. Individual [job logs and job metadata](2026-10-28-m2c-acceptance/)
  retain the exact evidence; all required markers were checked.
- Three safe-mode owner/recovery jobs ran Elixir 1.17.3 with OTP 25.3.2.21,
  26.2.5.21 and 27.3.4.19 on Ubuntu 24.04. Each included caller-gap death,
  VM/guardian/native loss, handled retirement and the runnable example. Two
  Ubuntu 26.04 jobs ran Elixir 1.20.4 / OTP 29.1.2 in debug and safe. Six
  independent native OTP 25/26/27 wire jobs passed in both modes; their M2b
  batch/monitor markers and the main job's external watchdog marker were checked.
- On that exact master in Linux x86-64 WSL with Zig 0.17.0 and Elixir 1.20.4 /
  OTP 29, `zig build test-all test-labs test-task-lifecycle test-worker-recovery
  -Doptimize=<debug|safe> -j2 --summary all` passed **73/73** steps per mode.
  Each final run executed **35/36** Zig checks with one conditional skip; other
  steps were cached. The owner suite ran ten tests, the process suite five;
  the M1 ordinary/private-EPMD runs were complementary (13 plus one case).
- Pinned Docker OTP 25/26/27 in each mode passed **7/7** steps, three targets,
  none missing. Each mode recorded three actual-CLI EPMD-loss markers and three
  two-worker discovery/hash/batch/reconnect/monitor markers. Docker/WSL evidence
  is not a native-host soak or general production compatibility claim.

## Retained failures and limits

The [restart barrier record](../phase-a/2026-10-29-m2c-restart-barrier.md)
retains an initial owner-kill failure and a controlled old-launcher counterexample;
waiting for old connection/name cleanup repaired the reproducible class without
claiming the unique historical cause. The [process-fault record](2026-10-29-m2c-process-faults.md)
retains a failed large-payload paused-peer run and a private EPMD readiness
failure whose causes were not captured. Later isolated runs passed.

A separate [traced pressure probe](2026-10-28-m2c-send-pressure.md) reproduced
`:nosuspend` and process-wide `worker_lost` with two 1 MiB calls to a stopped
child in ten local VMs. This is a real availability limit, not proof of the
original failure's unique cause or a throughput/RSS result. No OS-OOM/corruption,
security audit, untrusted-network deployment or native-host soak is established.

Earlier M2c unit filenames retain the `2026-10-29` ledger label; the captured
local and CI execution timestamps are **2026-10-28 UTC**, not a claim that the
runs occurred on the filename date. Revert owner, hooks, tests and related docs
as coherent units; retain historical evidence and the M1/M2b contracts.
