# M2c caller, disconnect and owner faults — 2026-10-29

With the [bounded restart barrier](../phase-a/2026-10-29-m2c-restart-barrier.md),
the owner campaign exercises:

- caller death after admission but before delivery;
- caller death with both actors holding work;
- distribution disconnect with two uncertain requests, replacement PIDs, and
  injection of an old reference while a new request is pending;
- owner SIGKILL with two uncertain requests, guardian cleanup and replacement.

The old request results are not replayed. A stopped child makes the requests
uncertain; these tests do not claim native acceptance or exactly-once effects.
Tests poll owned PID state and check the replacement with a new exact hash.

Linux/WSL Elixir 1.20.4 / OTP 29: the expanded eight-test owner suite passed
in 20 fresh VMs after the barrier was ordered before the owner. Zig 0.17.0
`test-all test-labs test-task-lifecycle test-worker-recovery` passed 73/73 steps
in debug and safe; 35/36 newly executed Zig checks passed with one conditional
skip per mode and remaining steps cached. M1/M2b recovery and the external
watchdog passed. Guard/VM loss, restart intensity and the full matrix remain
separate acceptance gates. Revert these test cases and this evidence together.
