# Compiled handler: live interoperability and faults

**Scope:** candidate based on example candidate `755de35`; Linux WSL2 x86-64, Zig 0.17.0, local Elixir 1.20.4 / OTP 29.1.1, and pinned OTP 25/26/27 Docker images. Final actual-master CI is a separate gate.

`test-interop` and `test-interop-docker` now build/install the separate custom example and require its executable; a missing executable is a failure, not a skipped target. `otp_custom_smoke.sh` independently exercises real OTP discovery of distinct PIDs, 0/3/32-byte binary calls, mode rejection, clean reconnect with stable live PIDs, an actual 33-byte handler failure and monitor exit, sibling progress and controlled stop. Existing M1/M2b smoke and isolated EPMD-loss checks still run.

`custom_worker_test.exs` additionally checks nonbinary rejection, disconnect and reconnect after an input exceeding 1 MiB, no `call` on the original SHA-256 service, and external native SIGKILL while a sent call is uncertain. The BEAM VM and an unrelated process stay responsive; an explicitly launched replacement has a different PID, accepts fresh work and does not answer the old reference. A successful send before SIGKILL does **not** prove whether the old operation executed, and this test does not establish exactly-once execution. Guard and child death are observed after each scenario. No automatic replay is introduced.

## Local checks

```sh
zig fmt --check build.zig src tests examples
zig build test-all test-labs test-task-lifecycle test-worker-recovery -Doptimize=debug -j2 --summary all
zig build test-all test-labs test-task-lifecycle test-worker-recovery -Doptimize=safe -j2 --summary all
zig build test-interop-docker -Doptimize=debug -j2 --summary all
zig build test-interop-docker -Doptimize=safe -j2 --summary all
```

Both full modes passed **76/76 steps, 37/39 newly executed Zig checks with two conditional skips**; other Zig steps were cached. Both external-kill watchdog probes passed; each run executed the 15-case owner suite, the live example and the 3-case custom fault suite. The final custom fault suite also passed **3/3 in ten additional fresh OTP 29 VMs**.

Both pinned Docker modes passed **9/9 steps, three target entries and none missing**. Each of OTP 25, 26 and 27 emitted its custom-profile marker and existing-profile markers. The Docker runner uses host networking for the OTP service checks and a separate isolated container for EPMD-loss testing. Logs are `~/.local/state/zbeam-maintenance/2026-10-29-m2d/handler-interop-{full,docker}-{debug,safe}.log` and `handler-interop-final-{1..10}.log`.

At this local checkpoint, Elixir 1.17/OTP 25–27 execution of this fault suite, actual merged-master CI, native-host soak, total RSS, security review and production readiness were separate gates. The M2c SHA-256 owner does not expose custom calls; raw BEAM senders are not bounded by that owner.

## Actual merged-master follow-up

PR #56 merged as `8dec4ce82580592d7df5f71aeccf4d830cd45d7d`. [Actual-master CI 42132194253](https://github.com/rickyraz/zbeam/actions/runs/42132194253) passed **12/12**: five Elixir/recovery lanes ran the 3/3 custom fault suite, 15/15 owner and 6/6 process/oracle cases; each of the six OTP 25/26/27 debug/safe wire jobs reported the custom call/reconnect/handler-failure/stop marker with one target and none missing. The earlier actual-master [failure 42103993219](https://github.com/rickyraz/zbeam/actions/runs/42103993219) is retained and its test-oracle repair is [separately recorded](2026-11-05-restart-oracle.md). This checkpoint used SIGKILL, not an injected custom-handler panic; [the subsequent panic fixture](2026-11-05-handler-panic.md) has its own evidence and gates. Production acceptance remains open.

**Rollback:** revert the live custom test/matrix additions and documentation together; the previously implemented example and SHA-256 profiles remain.
