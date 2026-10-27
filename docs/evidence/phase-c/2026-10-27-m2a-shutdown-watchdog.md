# M2a noncooperative shutdown boundary

`zig build test-task-lifecycle` runs the deterministic lifecycle tests and a
Linux subprocess probe. The probe enables a test-build-only spin in actor A.
After observing actor entry it reaches the actual Future-cancel vtable call,
then deliberately cannot complete join. The Python parent requires both markers,
observes the eight-second stall, kills only its owned child and reaps SIGKILL.
An early clean exit is rejected; no timeout is reported as successful shutdown.

Linux x86-64 WSL2 / Zig 0.17.0, lifecycle merge base `3d8c531`:

- Full `test-all test-labs test-task-lifecycle` in each mode: 67/67 steps,
  77/79 newly executed tests passed, **two conditional spin cases skipped**;
  unaffected runs cached. The separately spawned opt-in probe passed in each.
- Ten additional fresh watchdog trials per mode: 20/20 expected stalled joins,
  each with `M2_SPIN_ENTERED` and `M2_JOIN_WAIT`, followed by exact kill/reap.
  This is 20 process-boundary checks, not 20 successful in-process shutdowns.
- `/bin/true` negative control exits cleanly but is correctly rejected by the
  watchdog; its expected counterexample traceback is retained with raw logs.
- Normal test runs explicitly disable the spin; only the test-owned subprocess
  receives `ZBEAM_M2_SPIN_PROBE=1`. Production builds have no spin/pause/fault API.
- CI runs the explicit lifecycle target in debug and safe. Formatting/whitespace
  checked; raw build, focused, marker and negative-control logs retained adjacent.

The supervisor deadline does not free runtime storage while tasks are alive.
This proves a cooperative-join limit and external process cleanup, not actor-local
panic/corruption isolation, native-host certification or an OS-OOM guarantee.
Final integrated M2a acceptance/OTP/owner gates remain pending. Rollback removes
only the watchdog test, opt-in build target/CI steps and associated evidence.
