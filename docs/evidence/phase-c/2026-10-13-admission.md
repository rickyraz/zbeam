# Bounded local admission and two-process progress control

**Decision:** keep the caller-scheduled registry and conservative shared-wire admission contract. Do not introduce a production multi-actor scheduler from this experiment.

Zig 0.16.0 Debug and ReleaseSafe `zig build test-all -j2` passed **56/56**. Twenty additional ReleaseSafe `test-stress` runs passed. The added stress scenario runs two existing mailboxes, each with four fixed slots of an inline-owned 1024-byte message. One worker holds its active message behind an event; its queue fills, an extra send races termination, and admitted work on the second worker progresses. Both closed queues drain and every task joins before registry/mailbox storage is destroyed. A raced sender can observe `Closed` or `ActorNotFound`; this test does not force both resolution orderings in every run. No external packet pointer crosses the queue.

The separate OTP 29/Elixir control ran ten trials with two test-owned OS workers and connections. One pauses for 1500 ms while the other completes 100 exact-digest requests in under one second; the slow request then completes. This establishes independent-process progress on the same four-visible-CPU WSL2 host, not equal-cost throughput against local mailboxes.

The [admission ADR](../../adr/0002-bounded-two-worker-research.md) requires minimum destination capacity when the next frame destination is unknown. The assertion rejects a sum of `{0,4}` credits as permission to read. There is still no shared-connection multi-actor dispatcher; head-of-line blocking is explicitly accepted rather than hidden by an unbounded route queue. The fixed-slot test counts queued and active messages separately, not arbitrary allocator/OS memory.

```sh
zig build test-all -j2
zig build test-all build-research-peer -j2 -Doptimize=ReleaseSafe
zig build test-stress -j2 -Doptimize=ReleaseSafe
epmd -daemon
ERL_FLAGS='+S 2:2 +SDcpu 2 +SDio 1' elixir --name progress@127.0.0.1 \
  --cookie research_cookie benchmarks/two_process_progress.exs \
  "$PWD/zig-out/bin/zbeam-research-peer"
```

Raw logs: `2026-10-13-admission/`. Production scheduling, dynamic-size accounting, exhaustive termination interleavings, sanitizers/TSAN and a matched two-actor versus two-process throughput study remain unverified.
