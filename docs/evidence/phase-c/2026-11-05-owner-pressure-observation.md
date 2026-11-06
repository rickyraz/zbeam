# Owner queue and memory observation

**Scope:** three fresh BEAM VMs on Linux WSL2 x86-64, Elixir 1.20.4 / OTP 29.1.1, Zig 0.17.0 `safe`, two BEAM schedulers, local IPv4, 5 November 2026 UTC. This is a short functional observation, not a native-Linux soak or production capacity benchmark. Full logs are `~/.local/state/zbeam-maintenance/2026-10-29-m2d/pressure-sample-{1..3}.log`.

The self-checking `benchmarks/owner_pressure.exs` pauses its owned worker, starts 80 callers with 256-byte inputs, and waits for the replies that can complete. Each run observed 78 `busy` responses, two admitted slots, and after resume two exact digests. It then verified 2,000 sequential exact SHA-256 responses, stopped the supervisor and observed both owned processes exit.

| Point / metric | Three-run observed range |
|---|---:|
| Idle BEAM VmRSS | 105,184–107,848 KiB |
| Stopped worker, after 78 busy replies: BEAM VmRSS | 103,780–105,912 KiB |
| Stopped worker: native VmRSS | 2,896 KiB |
| Stopped worker: BEAM `:total` | 59,257,792–60,145,992 bytes |
| Stopped worker: owner process memory | 11,372 bytes |
| Stopped worker: owner mailbox / distribution port queue | 0 messages / 0 bytes at sampling |
| After 2,000 requests: BEAM VmRSS | 108,484–110,888 KiB |
| After 2,000 requests: native VmRSS | 3,768–4,056 KiB |
| After 2,000 requests: BEAM `:total` | 59,437,872–60,352,008 bytes |
| Short sequential run wall time, including harness work | 882–1,103 ms |

`/proc/PID/status` VmRSS and BEAM allocator totals measure different things and must not be added as a per-request cost. The owner mailbox, process memory, admission table and distribution-controller queue are instantaneous snapshots, not peaks. The owner state poll and 2-second wait precede the stopped-worker snapshot; transient queues are missed. A distribution port queue size of zero does not include all BEAM distribution buffers or kernel socket buffers. This 256-byte workload did not establish `:nosuspend` saturation; the [separate pressure test](2026-11-05-owner-send-pressure.md) exercises that behavior. VM processes, binaries retained by callers, arbitrary BEAM messages, kernel memory, long-term RSS growth, fairness and maximum latency remain unbounded by this observation.

```sh
zig build -Doptimize=safe
sh scripts/interop/ensure_epmd.sh
elixir --erl '+S 2:2' --name pressure_sample@127.0.0.1 --cookie development_cookie \
  benchmarks/owner_pressure.exs ./zig-out/bin/zbeam
```

Only run against the self-launched child; SIGSTOP/SIGCONT are Linux-specific. The sample does not perform a long soak, test an untrusted network or measure a custom handler.
