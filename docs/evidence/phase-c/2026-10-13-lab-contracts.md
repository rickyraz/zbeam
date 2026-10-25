# Executable lab contracts

## Scope and environment

The experiments extend `labs/`, not the production API. Base: `master` at
`11c3319`. Execution: 2026-10-13, Zig 0.16.0, Linux x86-64 WSL2 kernel
6.18.33.2-microsoft-standard-WSL2. Builds use `-j2` while unrelated research may
run on the host; timings are not benchmark results. No external OTP, EPMD,
packet capture or compiler replacement is required.

## Mailbox and demand observations

Commands from the worktree root:

```sh
timeout 240 zig build test-labs -j2 --summary all
timeout 240 zig build test-labs -j2 -Doptimize=ReleaseSafe --summary all
timeout 240 zig build test-all -j2 --summary all
```

All commands use Zig 0.16.0 from an explicit compiler path; shell-default Zig
0.17.0 is not compatible with the current `Build.args` in `build.zig`.

- [Lab 01–02 raw output](2026-10-13-lab-contracts/01-02-debug.log): exit 0,
  4/4 lab tests passed. Lab 01 checks 11,904 deliveries over 15 producer/capacity
  combinations and close/drain behavior. Lab 02 records 24 observation states;
  inactivity does not distinguish missing grants from long work or grant credit.
- [Core regression](2026-10-13-lab-contracts/core-debug.log): exit 0; unit,
  integration, conformance and stress suites passed.

Zig 0.16's build runner labels test stderr with `failed command` even when the
process succeeds. Lab traces use stderr; the command exit status and final test
summary determine success, not that diagnostic label.

## Framing, backpressure and connection cleanup

`timeout 240 zig build lab-03 lab-04 lab-08 -j2 --summary all` exited 0:
[5/5 tests passed](2026-10-13-lab-contracts/03-04-08-debug.log).

- Lab 03: 100 paused attempts produce zero reads/allocation attempts; a single
  grant consumes five bytes and leaves the next four-byte tick untouched.
- Lab 04: seven incomplete frame prefixes consume old credit and leave no
  outstanding packet bytes; each explicitly fresh state reads the complete frame.
- Lab 08: eleven short-read cases allocate/free seven bytes exactly once;
  oversized frames fail before allocation and OOM leaves the payload unread.

These are counted-reader experiments against production framing, not measured
TCP windows, automatic reconnect, io_uring or performance results. Existing core
socket tests remain the network regression boundary.

## Representation, identity and handle limits

`timeout 240 zig build lab-07 lab-10 lab-11 -j2 --summary all` exited 0:
[6/6 tests plus the expected compile failure passed](2026-10-13-lab-contracts/07-10-11-debug.log).

- Lab 07: one boundary decode, no local re-encode, five payload bytes copied
  into a 48-byte inline envelope on this target. The source allocations are
  released before mailbox use; shape/range/capacity checks pass.
- Lab 10: 48 identities and 1,128 distinct pairs reject stale comparisons;
  255 increments exhaust an eight-bit generation without wrap. Composite
  identity occupies 16 bytes versus a four-byte slot on this target.
- Lab 11: direct access is rejected at compile time with the specific diagnostic,
  but field access and prior aliases remain legal. A sequential flag rejects a
  second call on one value; copying that value duplicates its state.

The conclusion is narrower than a zero-copy or linear ownership claim. Tuple
identity assumes non-reused connection incarnations and does not retain memory.
Typestate method removal does not close Zig's field/alias escape paths.

## Protocol policy, fan-out and sizing

`timeout 240 zig build lab-12 lab-14 lab-15 -j2 --summary all` exited 0:
[7/7 tests plus the expected compile failure passed](2026-10-13-lab-contracts/12-14-15-debug.log).

- Lab 12: both legal handshake role sequences type-check; invalid idle ACK is
  rejected at compile time; malformed tag/digest/shape tests do not advance the
  existing runtime FSM; the valid authenticated ACK completes it.
- Lab 14: broadcast waits for minimum credit and spends none on a failed
  reservation; finite round-robin partitions `[4,4,4]` and `[4,1,0]` exactly.
  This does not implement an atomic multi-mailbox dispatch.
- Lab 15: 9 pool combinations account for reserved bytes, fit counts, fallback
  payload bytes and cumulative padding. Synthetic results are not sizing advice.

## Aggregate verification

| Command | Result | Raw record |
|---|---|---|
| `zig build test-labs -j2 --summary all` | 36/36 steps; 22/22 tests passed | [Debug labs](2026-10-13-lab-contracts/all-labs-debug.log) |
| `zig build test-labs -j2 -Doptimize=ReleaseSafe --summary all` | 36/36 steps; 22/22 tests passed | [ReleaseSafe labs](2026-10-13-lab-contracts/all-labs-release-safe.log) |
| `zig build test-all -j2 --summary all` | 27/27 steps; 47/47 tests passed | [Core regression](2026-10-13-lab-contracts/core-debug-final.log) |

Four labs remain plans (05, 06, 09, 13): current code has no arena lifecycle,
local transfer path, alternate transport backend or general scheduler to measure.

## Limits and rollback

Lab 01 is sampled concurrency evidence, not a schedule proof or sanitizer run.
Lab 02 is a logical-time observation model, not handler preemption or a runtime
watchdog. No production implementation or public lifecycle contract changes.
Remove the lab build steps, experiments and their documentation to roll back;
production modules have no imports of these files.
