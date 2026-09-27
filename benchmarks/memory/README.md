# Allocator Experiments

Experimental branches leave the default application allocator as `process` (`std.process.Init.gpa`). No battery depends on the application selector. `-Dallocator=debug|smp|libc` selects only the allocator passed into the CLI runtime; startup/I/O allocation is still controlled by Zig's process initialization. `-Dlink-libc=true` supplies a matched libc-linked control. Selecting `libc` requires libc automatically.

## Checks and workloads

```sh
zig build test-allocators -Dallocator=smp -Doptimize=ReleaseSafe
zig build bench-allocators -Dallocator=smp -Doptimize=ReleaseSafe -- echo 2000 4096 /tmp/echo-samples.tsv
zig build bench-allocators -Dallocator=smp -Doptimize=ReleaseSafe -- handoff 2000 4096 /tmp/handoff-samples.tsv
```

The Linux-only executable reads `/proc` through a streaming reader with fixed scratch storage. Each process warms up, executes three cycles, and samples memory immediately and after 100 ms idle. These cycles are correlated; compare medians per process before aggregating independent launches.

- `echo`: the existing synchronous `Echo.handle` decodes a REG_SEND, encodes SEND, verifies the exact reply and releases it. Request/expected bytes and sample storage are outside the timed allocator path. This is not a socket round trip.
- `handoff`: two real OS-thread producers allocate/fill buffers; a main-thread consumer validates and frees them. A 128-slot `std.Io.Queue` bounds buffering to at most 131 live messages including producer/consumer-local ownership. Every free is cross-thread. Throughput includes worker startup/join; per-message latency spans allocation, queue admission/wait, validation and free. It is not an allocator-only nanobenchmark.
- Profiling uses `std.testing.FailingAllocator` with failure disabled for one untimed operation. Counts are successful allocations, logical requested/grown bytes and successful resize/remap calls, not physical allocation size, copy counts or CPU/syscall attribution. Timed work does not use that wrapper.
- RSS/HWM include the process, I/O backend and measurement state. Three cycles and 100 ms idle do not prove long-term reclamation or production leak freedom.

Raw samples are optional in single runs, mandatory in the matrix. Reported percentiles use nearest rank. Checks include allocation-failure cleanup, over-aligned realloc preservation, bounded remote handoff, and the procfs zero-size-file regression.

## Predeclared comparison

Use 32, 4096 and 65536-byte payloads; five independent launches per variant/workload; 2000 isolated operations per cycle and 1000 network round trips. Run serially in seed-260927 shuffled order. The network benchmark retains its Port comparison, and `ZBEAM_BENCH_PAYLOAD_BYTES` selects the payload within the Port's 1 MiB limit.

Build each variant into its own prefix, avoiding rebuilds during measurement:

```sh
zig build -j2 -Doptimize=ReleaseSafe -Dallocator=smp -Dlink-libc=true -p /tmp/zbeam-smp-libc
zig build build-allocator-bench -j2 -Doptimize=ReleaseSafe -Dallocator=smp -Dlink-libc=true -p /tmp/zbeam-smp-libc
python3 scripts/bench/allocator_matrix.py /tmp/allocator-results smp-libc=/tmp/zbeam-smp-libc
```

The matrix requires Python 3, Elixir/EPMD and the three prebuilt binaries in each prefix. It fixes BEAM schedulers to two. `--skip-network` explicitly selects an isolated-only run. The output directory must not already exist; failed jobs do not produce `COMPLETE`.

Artifacts include binary/source hashes, commands/stdout/stderr, both summary tables and compressed individual samples. Every recorded percentile is recomputed from raw samples before a run is accepted. Workload-specific distributions are not pooled into one score.

Baseline variants: `process-nolibc`, `smp-nolibc`, `debug-libc`, `smp-libc`, `libc`. Later snmalloc comparisons must use the matched libc controls. The [predeclared promotion criteria](../../docs/snmalloc-evaluation.md#e3--promotion-decision) still apply. WSL2, echo-only network traffic and this short experiment cannot close native-host, useful-job, long-soak or production-safety gates.
