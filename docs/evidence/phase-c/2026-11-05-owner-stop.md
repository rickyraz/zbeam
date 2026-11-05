# Per-actor stop through the supervised owner

**Scope:** candidate based on pressure change `6e4304690c8d0f360f2e98fd25dccb600f3c2559`, merged to master as `911cae5278efac509ba43009bed3cfdccf6e9f80`. Linux WSL2 x86-64, Elixir 1.20.4 / OTP 29.1.1, Zig 0.17.0. No native or wire-profile behavior changes.

## Contract

`TwoWorkerOwner.stop(name, :a | :b)` shares the existing pre-mailbox ticket with `hash`. An in-flight hash or stop makes another request to that actor return `busy`; stop does not cancel it. A matching stop `:ok` retires only that actor; subsequent calls return `unavailable`, while its sibling remains usable. Distinct pending operation tags prevent a hash reply from completing a stop or vice versa. A confirmed-unsent `:nosuspend` releases its ticket and returns `busy`. Once sent, a dead caller, disconnect or timeout retains process-wide fail-closed cleanup and never replays the uncertain stop.

## Verification

- The owner suite passed **15/15 in each of five fresh OTP 29 VMs**. It exercises independent retirement, invalid/retired actors, busy admission, mismatched reply types, unsent stop under real distribution pressure, caller death and timeout during uncertain stops, sibling failure/replacement and fresh work. The original 14-case preliminary run also passed before the timeout case was added.
- `examples/supervised_two_workers.exs` passed after additionally stopping `a` and hashing through `b`.
- `zig fmt --check build.zig src tests examples` passed. Each of the following passed **73/73 steps; 35/36 newly executed Zig checks, one conditional skip**, with other Zig test steps cached. Each run executed the Elixir owner and process-recovery checks, including all 15 owner cases.

```sh
zig build test-all test-labs test-task-lifecycle test-worker-recovery -Doptimize=debug -j2 --summary all
zig build test-all test-labs test-task-lifecycle test-worker-recovery -Doptimize=safe -j2 --summary all
```

Logs: `~/.local/state/zbeam-maintenance/2026-10-29-m2d/stop-{first,repeat-1,repeat-2,repeat-3,repeat-4,repeat-5,example,full-debug,full-safe}.log`. The conditional spin case is exercised separately by the external-kill watchdog. Other OTP versions and actual merged-master CI are separate gates. This is not preemption, exactly-once execution, a physical-memory bound or production certification.

**Rollback:** revert this owner API, example, tests and documentation together; the separately accepted wire stop remains available.
