# Compiled stateless handler: local lifecycle

**Scope:** local candidate based on ADR 0006 candidate `008b07c1804ce151e7bda948081b6d92e1113c26`; Linux WSL2 x86-64, Zig 0.17.0, Elixir 1.20.4 / OTP 29.1.1. This unit does not expose custom wire routing.

`TaskRuntime.createWithHandler` takes one compiled function shared by both actors. The runtime copies input through existing admission and passes it as a temporary borrow; it zeroes a 32-byte inline output buffer and records the returned 0–32-byte length alongside the existing outcome. Default SHA-256 creation and its `.digest` field remain unchanged; a SHA-256 result's `output_len` is 32. User code is responsible for not retaining buffers, not creating unmanaged tasks and being safe under concurrent calls. Zig does not enforce these obligations.

The new local tests cover empty and 32-byte results on distinct actors, copied input, zeroed unused output bytes, returned errors, invalid length 33, actor retirement and sibling progress. The original lifecycle/conservation tests remain. The watchdog now launches separate subprocesses for the original test spin and an actual noncooperative compiled function: in each, join stalled and the external harness killed and reaped its child. This is not preemption or safe in-process destruction while work runs.

## Checks

```sh
zig fmt --check build.zig src tests examples
zig build test-all test-labs test-task-lifecycle test-worker-recovery -Doptimize=debug -j2 --summary all
zig build test-all test-labs test-task-lifecycle test-worker-recovery -Doptimize=safe -j2 --summary all
zig build test-interop-docker -Doptimize=safe -j2 --summary all
```

Both full modes passed **73/73 steps, 130/134 newly executed Zig tests with four conditional skips**: the two opt-in spins appear in both unit and lifecycle runs, and each is exercised separately by its kill/reap subprocess. Other steps were cached. The full owner suite passed 15/15 in each mode. The Docker safe wire regression passed **7/7 steps, OTP 25/26/27 all present**; the native executable compile was cached. It covers the unchanged SHA-256 profiles, not custom wire handlers.

The first local compile failed because Zig 0.17 rejects the old array-repeat syntax used in a test; it was replaced with typed `@splat`. The failure and successful logs are retained under `~/.local/state/zbeam-maintenance/2026-10-29-m2d/handler-local-debug-first.log`, `handler-final-{debug,safe}.log` and `handler-otp-docker-safe.log`. Actual merged-master CI remains a separate gate. No RSS bound, arbitrary user-state lifetime, panic isolation or production claim is made.

**Rollback:** revert the local handler, length accounting, watchdog extension, tests and documentation together; existing SHA-256 wire behavior remains the baseline.
