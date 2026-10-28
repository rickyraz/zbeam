# M2c non-suspending send under a paused peer — 2026-10-28 UTC

The [process-fault record](2026-10-29-m2c-process-faults.md) preserves an
initial failed 1 MiB paused-peer trial without a captured cause. A separate
controlled probe traces `:erlang.send/3` returns from the owner while the owned
native process is stopped and two 1 MiB calls are admitted. On Linux/WSL,
Elixir 1.20.4 / OTP 29 and Zig 0.17.0, ten fresh VMs each observed one `:ok`
and one `:nosuspend`; both callers received `{:error, :worker_lost}`. This
establishes a reproducible failure mode, not the unique cause of the earlier
untraced failure or a result for every OS, OTP or socket configuration.

Reproduce on an isolated local node with a built executable and EPMD:

```sh
sh scripts/interop/ensure_epmd.sh
elixir --erl '+S 2:2' --name pressure_probe@127.0.0.1 --cookie development_cookie \
  docs/evidence/phase-c/2026-10-28-m2c-acceptance/nosuspend_probe.exs ./zig-out/bin/zbeam
```

The probe supervises and stops only its own child. `:nosuspend` can make the
owner fail closed and retire both actors; admitted work is not guaranteed to be
sent or completed. The experiment is not a BEAM queue-size, RSS, fairness,
throughput or production availability measurement.
