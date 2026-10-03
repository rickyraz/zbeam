# Matched native worker comparison

Optional benchmark-only Mix project pinned to Zigler 0.16.0 with `mix.lock`. NIFs use Zig 0.16.0 ReleaseSafe, direct binary marshalling, and normal/dirty CPU/threaded scheduling. They do not add ETF serialization. Native workers use the same SHA-256 implementation from the Zig standard library. The separate ETF Port uses the existing bounded ETF codec; the old raw-Port runner remains unchanged.

```sh
zig build build-research test-research -j2 -Doptimize=ReleaseSafe
(cd benchmarks/zigler && mix deps.get && ZIG_EXECUTABLE_PATH="$(command -v zig)" ERL_FLAGS='+S 2:2 +SDcpu 2 +SDio 1' mix test)
python3 scripts/bench/native_matrix.py --self-test
python3 scripts/bench/native_matrix.py /tmp/native-results --repeats 10 --iterations 1000
```

Run the matrix serially, without concurrent builds or other research workloads. Its children inherit the launcher's CPU affinity; the manifest records that common total CPU set. All cases use two normal and two dirty CPU schedulers and one dirty I/O scheduler. One caller has one outstanding request; NIF thread creation is part of the threaded comparison, not excluded setup. Each case starts a fresh BEAM VM; each repetition shuffles the same cases with a recorded seed. Input creation, oracle computation, 100 warmup requests and startup are outside measurement. ETF encode/decode and result checking are inside timed requests. Large synchronous SHA-256 is conservatively excluded pending normal-scheduler eligibility evidence, not counted as a pass.

Output includes compressed individual samples, run-level summaries and paired bootstrap intervals, dependency/source/binary hashes, CPU ticks for BEAM plus worker, post-work/100 ms/1 s total RSS, and a 10 ms sampled whole-launch process-tree peak. The sampled peak includes startup and may miss short-lived spikes; it is not exact steady-state peak RSS. Raw CPU ticks may be zero for short cases because their resolution is coarse. Missing tools do not become fabricated syscall/copy counts. All errors abort the matrix without a COMPLETE marker. Percentiles are independently recomputed from raw samples before each row is accepted.

The NIF and ETF-Port paths have exact-result/malformed-input checks; the ETF worker also exercises allocation-failure cleanup. `mix test` tests adapters, while a small matrix exercises every adapter in a fresh VM (including lazy module loading). Dependency fetch/build time is not benchmark time. NIF builds remain outside the normal `zig build` dependency DAG.

These measurements are unloaded sequential evidence. Loaded-BEAM, batching, recovery and actor admission are separate research branches. WSL2 results cannot satisfy the native-host replication gate or establish a production winner. See [the shared research contract](../../docs/native-worker-research.md).
