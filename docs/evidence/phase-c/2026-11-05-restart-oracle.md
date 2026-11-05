# Restart test oracle: capture one replacement PID

**Original failure:** actual-master [CI 42103993219](https://github.com/rickyraz/zbeam/actions/runs/42103993219), commit `0643e1f14c7c3e9d18ccbdbf35ac7dad60d26d64`, Elixir 1.17.3 / OTP 26, failed one owner test with `:sys.get_state(nil)` in `recovered/3`; 11/12 jobs passed. The complete job log is preserved at `~/.local/state/zbeam-maintenance/2026-10-29-m2d/job-127513891317-failure.log` and remains available in the linked run.

The test checked `Process.whereis/1` twice inside a predicate and a third time after the predicate returned. A deterministic test lookup sequence of **old PID, nil, fresh PID** demonstrates that the old two-read predicate can accept a disappearance as a replacement: the first value is a PID and `nil != old` is true. The original log captured the final `nil` but not the intervening lookups; this is a supported failure class, not proof of the unique historical interleaving or of a production owner defect.

The test-only helper now reads once per poll and returns the observed new PID. Both owner and process fault suites pass that exact PID to state inspection. If that PID subsequently dies, the test still fails; it does not retry or conceal a crashed replacement. Existing PID, no-replay and owned-child checks remain.

**Local verification:** Linux WSL2, Zig 0.17.0, Elixir 1.20.4 / OTP 29.1.1. The deterministic counterexample and process suite passed **6/6 in 20 fresh VMs**; the owner suite passed **15/15 in 10 fresh VMs**. `zig fmt --check build.zig src tests examples` passed. Each `zig build test-all test-labs test-task-lifecycle test-worker-recovery -Doptimize={debug,safe} -j2 --summary all` run passed **76/76 steps, 37/39 newly executed Zig tests with two conditional skips**; other steps were cached and both watchdog subprocesses were killed/reaped. Logs use `oracle-{owner,process}-N.log` and `oracle-full-{debug,safe}.log` in the ledger above.

This fixes an auditable test-oracle race, not the original historical M2c startup timeout or production availability. OTP 25–27 and actual repaired-master CI remain separate gates.
