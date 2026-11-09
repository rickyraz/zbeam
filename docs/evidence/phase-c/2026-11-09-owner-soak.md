# Owner soak harness

- **Date:** 2026-11-09 UTC.
- **Base:** master `d49ae82b85365d9fc643db3dc226e59c9a7b03c9`.
- **Requirement:** repeatable concurrent load through the supervised owner, runnable on a native Linux host as well as WSL2.

## Harness

`benchmarks/owner_soak.exs EXECUTABLE sha256|custom SECONDS CALLERS` starts one
supervised `TwoWorkerOwner` and runs `CALLERS` tasks per actor until the deadline.
Each task draws a deterministic random payload size from
`[0, 1, 32, 256, 4 096, 65 536, 1 048 576]` (SHA-256) or
`[0, 1, 32, 33, 256, 4 096, 65 536]` (custom) and checks every result exactly.
`busy` is counted and retried after 1 ms; any other result, or a different owner
PID at the end, fails the run. A sampler records first/min/max/last native and
BEAM `VmRSS`, native `VmHWM`, BEAM total memory and owner queue length once a
second. Latency percentiles use one successful call in eight. The run then stops
the supervisor and waits for the guardian and native child to exit.

The manual [Soak workflow](../../../.github/workflows/soak.yml) runs both profiles
on an ubuntu-24.04 GitHub runner with Elixir 1.20.4 / OTP 29, defaulting to
600 s and four callers per actor. Its results are recorded separately.

## Local results

Linux WSL2 x86-64, Zig 0.17.0 (`-Doptimize=safe`), Elixir 1.20.4 / OTP 29.1.1,
`+S 2:2`, 120 s per profile, four callers per actor (eight tasks).

| Profile | Exact results | `busy` | ok/s | p50 / p99 / max latency | Native VmRSS min–max | Native VmHWM | BEAM VmRSS min–max |
|---|---|---|---|---|---|---|---|
| SHA-256 | 85 010 | 119 686 | 708 | 1 558 / 16 026 / 46 391 µs | 4 480–7 780 KiB | 8 012 KiB | 118 592–129 256 KiB |
| Custom | 247 997 | 350 980 | 2 066 | 788 / 3 030 / 10 117 µs | 4 624–5 496 KiB | 5 720 KiB | 99 156–114 224 KiB |

Both runs reported no failures and no owner restart; the owner queue never
exceeded two messages at the sampled instants. The SHA-256 profile includes
1 MiB inputs, which explains its higher native high-water mark and latency tail.
An earlier 20 s custom run of this harness found the
[split-write latency regression](2026-11-09-split-write-latency.md), fixed before
these runs.

Logs: `~/.local/state/zbeam-maintenance/2026-11-09-m3/soak-local-*-120s.log`.

## Limits

One host, one run per profile, WSL2 rather than native Linux. Samples are taken
once a second, so the maxima are not true peaks, and `busy` reflects deliberate
oversubscription (four callers for one admission slot per actor). These are not
RSS, latency, throughput or fairness bounds.

**Rollback:** remove the harness, workflow, README section and this record.
