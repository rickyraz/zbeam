# snmalloc Evaluation and Integration Plan

- **Status:** researched candidate; not linked, integrated or benchmarked in zbeam.
- **Review date:** 2026-09-26.
- **Upstream snapshot:** release `0.7.5`, commit `526c55bdffa17aae20a9a3d24fe68a7a3b8d9894`.
- **Project baseline:** MVP commit `090bb60`, Zig 0.16.0.
- **Decision:** preserve allocator injection; evaluate an optional backend before changing any default.

## Recommendation

snmalloc is worth testing for owned messages allocated on one worker thread and freed on another. That is a plausible future actor workload, not a measured property of the current synchronous echo service. The initial comparison must include Zig's existing standard allocators and must not equate allocator message passing with zbeam actor messaging.

The sequence is **measure the allocation path → test a minimal adapter → validate ownership and pressure behavior → compare representative workloads → decide**. No runtime/scheduler redesign is justified solely to fit an allocator.

The [development plan](development-plan.md) places this experiment alongside reliability work and makes default adoption conditional.

## Verified upstream findings

| Finding | Consequence for this project | Primary source |
|---|---|---|
| Remote frees are returned to the originating allocator using batched message passing | Test producer/consumer and batched-deallocation patterns, not just same-thread malloc/free loops | [S1], [S2] |
| The 0.7 release incorporated BatchIt and revised startup behavior | Do not use the 2019 paper as an exact description or performance prediction for current code | [S3] |
| GitHub's latest-release endpoint resolved to 0.7.5 at review time; the checked-out tag resolves to the SHA above | Pin the reviewed SHA; refresh the audit deliberately on upgrades | [S4] |
| The pinned CMake configuration defaults to C++20, with a legacy C++17 option | Verify the actual compiler configuration; older build prose alone is insufficient | [S5], [S6] |
| The upstream C shim supports a configurable static symbol prefix and C allocation/free/alignment entry points | Reuse that ABI rather than inventing a second C++ allocation engine | [S5], [S7], [S8] |
| Thread cleanup has several platform/runtime strategies | Test the exact Zig thread/I/O backend and libc combination, including teardown | [S9] |
| Upstream has optional hardening; `new.cc` also defines global C++ new/delete | Make hardening explicit and prevent accidental global overrides | [S10], [S11] |

The MIT license and notice are in the pinned upstream tree [S12]. Upstream performance claims are not zbeam measurements.

## Local findings that change the experiment

### Current ReleaseSafe is not a standard high-throughput allocator baseline

`src/main.zig` uses `std.process.Init.gpa`. In the installed Zig 0.16.0 `lib/std/start.zig`, `use_debug_allocator` is true for ReleaseSafe when libc is not linked. This build does not request libc, and inspection identifies `zig-out/bin/zbeam` as a statically linked ELF binary.

Therefore the recorded ReleaseSafe Port comparison exercises the diagnostic general-purpose allocator in zbeam, not an explicitly selected `std.heap.smp_allocator`. The Port worker also receives `process.Init`, but its per-message payload uses a fixed array rather than heap allocation. This explains an important configuration difference; it does **not** prove that allocation caused the observed latency gap.

Linking libc also changes Zig's default allocator selection in this configuration. A naive before/after snmalloc test can therefore accidentally change both allocator routing and process initialization policy. Explicit allocator selection and matched linkage are required.

Local source paths, hashes and inspection results are recorded in [the source audit](evidence/phase-a/2026-09-26-allocator-source-audit.md). The allocator interface is the Zig 0.16.0 four-function vtable, including `remap`; older three-function adapters are not the contract for this repository.

### LD_PRELOAD is not the primary integration route

Preloading a malloc replacement does not substitute for zbeam's explicit Zig allocator, and this binary is static. Adding a preload to the Elixir benchmark launcher can change the harness/BEAM side while leaving the intended zbeam path unchanged.

A preload experiment is meaningful only for a separately built dynamic/libc-routed test child with allocation routing proved. It must not be presented as a result for the current binary. The proposed primary route is a namespaced C ABI behind `std.mem.Allocator`.

### Existing boundaries already provide the required seam

`runtime.node`, the ETF codec, distribution framing and the local registry receive `std.mem.Allocator` explicitly. Those batteries should not import snmalloc, C++ types or allocator-specific lifecycle state. The application or isolated experiment chooses the allocator and supplies the existing interface.

```text
application / benchmark allocator choice
        │
        ├── explicit Zig standard allocator
        └── optional snmalloc adapter → namespaced C ABI → pinned upstream
        │
        └── existing std.mem.Allocator parameters
              → runtime / transport / protocol / ETF
```

This does not add a sixth public battery or behavior to the umbrella. Standalone ETF and actor users must retain a no-snmalloc/no-C++ dependency path.

## Proposed integration shape

These files/options are future work, not interfaces currently available in the build:

1. **Isolated experiment:** `benchmarks/memory/allocator_compare.zig` and an experiment-local `snmalloc_adapter.zig`. Keep this separate from the default executable and package dependency graph.
2. **Pin and build:** use the reviewed commit and record source checksum, C++ compiler, target ABI, CMake options, hardening, TLS cleanup, CPU flags and libc. Prove native Linux x86-64 first; do not infer other targets from it.
3. **Reuse the upstream C shim:** compile/link namespaced allocation entry points. Prefer upstream prefix support, for example `zbeam_sn_`, and the malloc shim rather than global `malloc/free` replacement.
4. **Avoid incidental interposition:** inspect the link map and symbols. The stock static archive also contains a `new.cc` object; ensure it is not pulled in to override C++ operators. A malloc-only build is preferable if selective archive linking cannot prove this property. Do not use whole-archive linkage blindly.
5. **Zig adapter:** implement the current `Allocator.VTable`, preserving alignment, OOM and ownership. No C++ exception may cross the C/Zig boundary.
6. **Promotion only after the gates:** move the accepted adapter to an application-side location such as `src/allocators/snmalloc.zig`; add an opt-in build choice and a pinned/lazy dependency. Names are proposals. The default and narrow battery consumers must continue building without that dependency/toolchain.

Using C++ headers does not establish that linking, TLS destruction, libc and exception/unwind support are unnecessary. The build spike must record the actual requirements instead of assuming that “header-only” means dependency-free.

### Minimal allocator contract

| Vtable operation | Initial strategy | Required verification |
|---|---|---|
| `alloc` | Call a verified namespaced aligned C entry point, such as `posix_memalign`; normalize alignment to the target ABI | Correct alignment for arbitrary supported powers of two, non-multiple lengths, null/error mapping to OOM and overflow checks |
| `free` | Use the matching namespaced **unsized** free | Same allocator domain; original pointer; exactly-once release even when another thread consumes the message |
| `resize` | Start with `Allocator.noResize` | No moving `realloc` hidden behind an in-place resize result |
| `remap` | Start with `Allocator.noRemap` | Caller fallback preserves data, alignment and the old allocation on failure |

The conservative resize/remap behavior is intentionally limited and must be reported in benchmarks. If buffer-growth paths dominate, evaluate a separately tested in-place capacity check rather than concluding that an unoptimized adapter represents all of snmalloc. Do not map ordinary C `realloc` blindly onto over-aligned Zig memory.

Unsized free avoids coupling initial correctness to physical size-class rounding or logical lengths changed by later resize behavior. Sized-free optimization is separate work requiring proof of the exact upstream size/alignment contract.

## Ownership and shutdown rules

- Every allocation must be released through its originating **allocator domain**, not whichever allocator happens to be convenient on the receiving thread.
- Cross-thread deallocation within one backend is not permission to mix `free`, `sn_free`, an arena reset and a Zig allocator's `free` on the same pointer.
- A message crossing an actor/task boundary needs an owning envelope or another explicit allocator/lifetime strategy. Byte slices alone do not establish ownership.
- Join/cancel application tasks and resolve queued ownership before destroying associated runtime storage. OS-thread/TLS teardown is different from actor termination.
- Test producer-thread exit while consumers still own its messages, idle producers receiving remote frees, worker churn and `std.Io.Group` cancellation with the actual selected backend.
- Per-term decode budgets and connection/mailbox admission limits remain required. Allocator caches, rounding and metadata can make physical memory exceed logical requested-byte totals.

snmalloc is not a solution for use-after-free, stale arena generations, missing credits or missing drop obligations. Its optional hardening is defense in depth, not a substitute for those contracts. A C-level guarded memcpy also does not prove that every Zig copy operation is routed through that function.

## Experiment sequence

### E0 — Baseline and cost attribution

Preserve the current MVP result, then add explicit labels and comparable variants:

- current `init.gpa` as a diagnostic/reference configuration;
- `std.heap.smp_allocator` as the first standard performance candidate;
- `std.heap.c_allocator` as a libc-routing control only where needed;
- a request-local standard arena only for scratch allocations whose entire lifetime ends with the request; no escaped payloads;
- snmalloc through the explicit adapter, both the chosen normal and hardening configuration where applicable.

Keep optimizer, CPU target, workload, packet limits, queue capacity, I/O backend and linkage constant in each comparison. In a snmalloc-enabled harness, include the explicit standard allocator arm under the same link configuration. Account separately for `process.Init`/I/O allocations that do not use the chosen application allocator.

Record allocation counts, requested bytes, remote-free ratio by OS thread, resize/remap/fallback counts and copied bytes. Profile CPU/syscall time as well as allocation time. An allocation profiler must not silently become the measured fast path; record instrumentation overhead separately.

### E1 — Adapter and platform correctness

The smallest required checks cover:

- zero-length API behavior, minimum sizes, size-class boundaries, 4 KiB/64 KiB alignment, large binary sizes and checked arithmetic;
- forced allocation failure, failed growth retaining original data, successful shrink/growth behavior and cleanup of partially decoded ETF terms;
- same-thread and remote-thread free, producer exit before consumer free, idle-origin cases and worker churn;
- queue close/drain, canceled handlers and connection teardown while owned messages remain;
- real `std.Thread` and `std.Io` worker/TLS behavior, not only a C++-only test program;
- independent battery builds, all existing deterministic tests and OTP target tests with the opt-in allocator;
- sanitizer/hardening checks where the toolchain supports the allocator configuration, with unsupported combinations reported explicitly.

Keep `std.testing.allocator`/debug ownership tests in the suite. Replacing them globally with a faster allocator would remove useful diagnostics.

### E2 — Representative performance matrix

| Workload | Purpose |
|---|---|
| Current sequential echo, several payload sizes | Check that the existing use case does not regress |
| Same-thread allocation/free | Control for workloads without remote frees |
| 1 producer/1 consumer and bounded MPSC handoff | Test the primary cross-thread hypothesis |
| Multiple producers/consumers, fixed total in-flight bytes | Examine scaling without disguising unbounded buffering as throughput |
| Bursts followed by idle and producer exit | Observe remote reclamation and retained memory |
| Malformed input, cancellation and reconnect loops | Validate cost and cleanup outside the happy path |
| Useful native worker job through both Port and distribution | Establish whether the larger product trade-off is worthwhile |

Use fixed seeds, identical byte/queue budgets, representative size mixtures, warm-up and cold-start runs. Choose worker counts relative to physical/visible CPUs; label oversubscription. Report p50/p95/p99, throughput, CPU, allocation/copy counts, peak and post-idle RSS, logical live bytes, thread-start cost, binary size and build/packaging cost. Sparse virtual address reservation is not the same metric as RSS.

Run repeated, interleaved comparisons on native Linux as well as the development WSL2 environment. Preserve raw samples and report uncertainty. Verify actual entry-point use with a counter or trace before trusting any allocator comparison.

### E3 — Promotion decision

The following are **proposed starting acceptance thresholds**, not measured results. Agree on workloads and thresholds before running the comparison; changes require a documented reason rather than post-hoc selection.

1. All correctness, ownership, bounds, cancellation and OTP gates pass. A faster unsafe configuration is rejected.
2. Against the explicit standard allocator, increase representative throughput or reduce p95 by at least 10%, repeatably outside measurement noise; do not rely solely on a synthetic remote-free benchmark.
3. No p99 regression greater than 5% on the other declared representative workloads, and no peak/post-idle RSS regression greater than the predeclared 10% budget. A different memory trade-off requires an explicit profile-specific decision.
4. No continued growth across equivalent repeated workload/drain cycles after warm-up. Distinguish a bounded retained cache from a leak; do not require RSS to fall to zero after every free.
5. Preserve the no-C++ default build and standalone batteries; document added compiler/libc/TLS requirements and a rollback path.

Possible outcomes:

- **Retain standard default:** standard allocation is sufficient or the benefit is below the threshold. Keep results, not a permanent unused adapter.
- **Optional specialized backend:** gains are real only for a documented remote-free-heavy deployment. Ship opt-in, never imply a universal improvement.
- **Consider a default change:** only after broad representative evidence, a maintenance decision and a separate reviewed change. This research plan does not authorize a default switch.
- **Reject/defer:** ownership, memory, portability or build-cost regressions outweigh the benefit.

## Evidence required before implementation claims

The current [source audit](evidence/phase-a/2026-09-26-allocator-source-audit.md) establishes only source/ABI observations and the baseline's linkage/allocator selection. No snmalloc binary was built, no adapter was compiled, and no snmalloc performance or security result was obtained for zbeam.

The next artifacts are a lab implementation, runnable contract tests, matched raw benchmark results and an allocator decision record. Until those exist, implementation status remains unchanged.

## Primary sources

Sources were reviewed on 2026-09-26. Pinned source links refer to the audited commit; a source audit does not establish integration compatibility.

- [S1] [Official snmalloc README](https://github.com/microsoft/snmalloc/blob/526c55bdffa17aae20a9a3d24fe68a7a3b8d9894/README.md).
- [S2] [Microsoft Research: snmalloc, a message-passing allocator](https://www.microsoft.com/en-us/research/uploads/prod/2020/04/snmalloc.pdf), 2019 design background, not the current implementation contract.
- [S3] [Upstream 0.7 release explanation: BatchIt and startup](https://github.com/microsoft/snmalloc/blob/526c55bdffa17aae20a9a3d24fe68a7a3b8d9894/docs/release/0.7/README.md).
- [S4] [Upstream release 0.7.5](https://github.com/microsoft/snmalloc/releases/tag/0.7.5); verified via the [latest-release redirect](https://github.com/microsoft/snmalloc/releases/latest) and a tag checkout.
- [S5] [Pinned CMake configuration](https://github.com/microsoft/snmalloc/blob/526c55bdffa17aae20a9a3d24fe68a7a3b8d9894/CMakeLists.txt).
- [S6] [Upstream build guide](https://github.com/microsoft/snmalloc/blob/526c55bdffa17aae20a9a3d24fe68a7a3b8d9894/docs/BUILDING.md); read with the pinned CMake configuration.
- [S7] [C ABI entry points](https://github.com/microsoft/snmalloc/blob/526c55bdffa17aae20a9a3d24fe68a7a3b8d9894/src/snmalloc/override/malloc.cc) and [prefix handling](https://github.com/microsoft/snmalloc/blob/526c55bdffa17aae20a9a3d24fe68a7a3b8d9894/src/snmalloc/override/override.h).
- [S8] [Allocation, alignment and realloc semantics](https://github.com/microsoft/snmalloc/blob/526c55bdffa17aae20a9a3d24fe68a7a3b8d9894/src/snmalloc/global/libc.h).
- [S9] [Thread allocator initialization/teardown](https://github.com/microsoft/snmalloc/blob/526c55bdffa17aae20a9a3d24fe68a7a3b8d9894/src/snmalloc/global/threadalloc.h).
- [S10] [Upstream hardening](https://github.com/microsoft/snmalloc/blob/526c55bdffa17aae20a9a3d24fe68a7a3b8d9894/docs/security/README.md).
- [S11] [Global C++ allocation overrides](https://github.com/microsoft/snmalloc/blob/526c55bdffa17aae20a9a3d24fe68a7a3b8d9894/src/snmalloc/override/new.cc).
- [S12] [Pinned license](https://github.com/microsoft/snmalloc/blob/526c55bdffa17aae20a9a3d24fe68a7a3b8d9894/LICENSE).
- [Z1] [Zig 0.16.0 release and source distribution](https://ziglang.org/download/0.16.0/release-notes.html); local `lib/std/start.zig` and `lib/std/mem/Allocator.zig` were inspected directly for the precise allocator-selection and vtable contracts.
