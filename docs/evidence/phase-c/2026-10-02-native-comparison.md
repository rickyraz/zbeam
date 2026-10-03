# Native comparison adapters — 2026-10-02

Branch: `explore/zigler-baseline`; parent planning commit `b37e0d1`. Environment: Zig 0.16.0, Zigler 0.16.0 (locked Hex dependencies), OTP 29.1.1, Elixir 1.20.4, Linux x86-64/WSL2, four visible CPUs. Native code is ReleaseSafe. NIFs are libc-linked with BEAM allocator/marshalling; workers retain their existing process allocator/fixed-storage policies. Those differences are measured end-to-end, not attributed solely to ETF.

Implemented: optional bounded ETF Port, direct Zigler echo/SHA-256 in normal/dirty CPU/threaded modes, fresh-VM randomized matrix, exact replies, raw samples, total RSS/CPU observations and run-level paired bootstrap intervals. Production behavior is unchanged. `build-research`/`test-research` are optional targets; Zigler dependencies remain in `benchmarks/zigler`.

Verification:

- `zig build test-all test-research -j2 --summary all`: 55/55 tests plus CLI passed.
- Same with `-Doptimize=ReleaseSafe`: 55/55 tests plus CLI passed.
- `zig build test-interop-docker -j2 -Doptimize=ReleaseSafe --summary all`: pinned OTP 25/26/27 all passed; no target missing.
- `mix test` with Zig 0.16.0 and two normal/two dirty CPU schedulers: two adapter suites passed, including exact binaries and oversized-input rejection in every NIF mode.
- `python3 scripts/bench/native_matrix.py --self-test`: percentile, paired resampling and real procfs sampling passed.
- Fresh-VM smoke: all twelve 32-byte job/path combinations passed. The initial smoke exposed lazy module loading before `String.to_existing_atom`; static function atoms fixed the adapter selection. The failed run is not performance evidence.

Logs are in [the evidence directory](2026-10-02-native-comparison/). The [runner documentation](../../../benchmarks/zigler/README.md) defines reproduction and limitations. Full repeated measurement is recorded separately when completed; smoke values do not establish a winner. Native Linux replication, loaded-BEAM control and fine-grained CPU/syscall/copy profiling remain required before promotion. `perf` and `strace` are not installed on this host. No default allocator or lifecycle contract changed.
