# Repository Scripts

**Status:** ETF fixture generation and OTP interoperability runners are available.

## Available workflows

- `test/cli_smoke.sh` protects redirected stdout and argument validation as part of the integration gate;
- `interop/generate_etf_fixtures.exs` regenerates checked-in ETF fixtures;
- `interop/otp_matrix.sh` validates configured OTP versions and runs the MVP contract suite, with strict missing-target failure available;
- `interop/otp_docker_matrix.sh` runs all three targets using pinned images and Linux host networking;
- `bench_port_vs_zbeam.sh` reports Port/distribution latency, throughput, memory snapshots, restart and scheduler activity.

Broader fault-injection and lab runners remain outside verification until implemented. Scripts must fail on command errors, record tool versions and avoid host-specific absolute paths. Interoperability/benchmark cookies are public test values; scripts must never embed deployment credentials. Core checks remain directly runnable through `zig build`.
