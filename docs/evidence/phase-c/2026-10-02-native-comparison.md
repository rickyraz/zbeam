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

## Threaded comparator quarantine — 2026-10-03

The first 1,000-request matrix stopped on an incorrect threaded echo result. Inspection of the pinned generated join adapter showed a raw `beam.term` from the thread environment passed through `beam.make` without copying into the caller environment. The adapter now uses `beam.send` and returns `void` instead of escaping that term. However, a subsequent 2,000-iteration varying-input stress still terminated the disposable test VM with SIGSEGV. The remaining cause is unresolved; short successful threaded runs do not establish safety.

The default matrix therefore refuses threaded scoring and records it as unavailable. Normal/dirty CPU modes remain eligible; this is not evidence that zbeam beats a threaded implementation. The quarantined reproducer is `cd benchmarks/zigler && mix test --include threaded_unverified`; it can terminate its test VM and must not be loaded into an application VM. The rejected run, source/binary hashes and diagnostic log are retained under `threaded-term-rejected/` and `nif-thread-ownership.log`. Default ExUnit results are two passing suites and one explicitly excluded threaded stress, not three passes.

Logs are in [the evidence directory](2026-10-02-native-comparison/). The [runner documentation](../../../benchmarks/zigler/README.md) defines reproduction and limitations. Full repeated measurement is recorded separately when completed; smoke values do not establish a winner. Native Linux replication, loaded-BEAM control and fine-grained CPU/syscall/copy profiling remain required before promotion. `perf` and `strace` are not installed on this host. No default allocator or lifecycle contract changed.
