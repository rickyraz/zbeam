# Repository Scripts

**Status:** ETF fixture generation and OTP interoperability runners are available.

## Available workflows

- `interop/generate_etf_fixtures.exs` regenerates checked-in ETF fixtures;
- `interop/otp_matrix.sh` runs the registered echo peer against configured OTP 25–27 executables and reports unavailable versions as skipped;
- `bench_port_vs_zbeam.sh` runs the initial local Port latency comparison.

Future benchmark, fault-injection, and lab runners remain outside release verification until implemented. Scripts must fail on command errors, print or record tool versions, avoid host-specific absolute paths, and accept secrets through the environment rather than source files. Core checks remain directly runnable through `zig build`.
