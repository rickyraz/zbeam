# Initial Erlang Port baseline

## Scope

Local round-trip latency for the same 32-byte payload through:

1. an Erlang Port using four-byte packet mode and a Zig echo process;
2. the current zbeam registered echo path over Erlang distribution.

This is baseline evidence, not a performance or superiority claim.

## Environment

- Linux 6.6.114.1 WSL2, x86_64
- AMD Ryzen 5 5600H, 4 visible CPUs
- Zig 0.16.0
- Erlang/OTP 28, ERTS 16.3

## Command

```sh
zig build
./scripts/bench_port_vs_zbeam.sh 1000
```

## Raw result

```text
implementation          iterations  payload_bytes  median_ns  p95_ns
erlang_port              1000        32             92369      144154
zbeam_distribution       1000        32             478470     653316
```

The initial zbeam path was approximately 5.2x slower at the median. The paths include different protocol overhead and this single local run is not statistically sufficient for optimization decisions. Memory, p99, scheduler impact, restart time, and repeated-run distributions remain unmeasured.
