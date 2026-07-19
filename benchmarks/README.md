# Benchmarks

Benchmarks are evidence tooling, not product claims. Results must record hardware, OS, Zig, OTP, command, payload, iteration count, and raw output.

## Erlang Port baseline

Build and compare a four-byte packet-mode Erlang Port echo with the current distribution echo path:

```sh
zig build
./scripts/bench_port_vs_zbeam.sh 1000
```

Both paths round-trip the same 32-byte payload from one BEAM process to one Zig process. The result reports per-message median and p95 latency. This is a local transport baseline, not evidence of throughput, production readiness, or superiority over Ports.
