# 64 KiB compiled-handler output

- **Date:** 2026-11-09 UTC.
- **Base:** master `e00cd9a989b2d969962e597e1c9067c43885034f`.
- **Requirement:** [ADR 0007](../../adr/0007-bounded-handler-output.md) step 3.

## Change

- `TaskRuntime.Handler` is `fn (input: []const u8, output: []u8) error{HandlerFailed}!usize`.
  `output` is exactly `TaskRuntime.max_output` (64 KiB), zeroed before each call.
- With a handler, the runtime allocates 11 × 64 KiB at creation: one buffer per
  completion ticket and one for the collected copy. SHA-256 runtimes allocate
  no extra storage; a test checks that only the runtime struct is allocated.
- `Result.output_len` is replaced by `Result.output`. `nextResult` copies the
  ticket's used prefix before the ticket can be reused; the copy is valid until
  the next `nextResult` call. `Outcome` is unchanged.
- The session sends `Result.output` through the step 2 header-plus-payload path
  and fails closed on a length above 64 KiB, releasing the output credit.
- `TwoWorkerOwner.call/3` accepts replies of up to 65 536 bytes. The example,
  panic fixture and test handlers use the new signature; the example now fails
  above 64 KiB instead of above 32 bytes.

## Tests

- Local runtime: outputs of 0, 32, 33 and 65 536 bytes on both actors; a returned
  length of 65 537 and a handler error each retire only one actor; a handler that
  fails on any nonzero byte proves each reused ticket buffer is zeroed, while a
  collected 1 000-byte copy stays intact while four more requests reuse that
  actor's tickets, including the first request's ticket.
- Session: exact replies of 0, 3, 32, 33 and 65 536 bytes; an oversized result
  fails closed and its credit is released.
- Live OTP (`otp_custom_smoke.sh`): a 65 536-byte call and reply, and handler
  failure at 65 537 bytes, on pinned OTP 25/26/27.
- Elixir: the raw custom tests and the custom owner suite use 65 536-byte
  success and 65 537-byte handler failure.

## Local results

Linux WSL2 x86-64, Zig 0.17.0, Elixir 1.20.4 / OTP 29.1.1, Docker.

- `zig fmt --check build.zig src tests examples` passed.
- `zig build test-all test-labs test-task-lifecycle test-worker-recovery
  -Doptimize={debug,safe} -j2 --summary all` passed 77/77 steps in each mode
  (debug 55/57 and safe 143/147 newly executed tests; only the watchdog-gated
  cases skipped; other steps cached). Owner 15/15, process 6/6, raw custom 4/4
  and custom owner 5/5 passed in both modes.
- `zig build test-interop-docker -Doptimize={debug,safe}` passed all three pinned
  OTP targets, none missing, in each mode.
- Logs: `~/.local/state/zbeam-maintenance/2026-11-09-m3/output64-*.log`.

## Limits

This raises one fixed bound; it does not add streaming results, outputs above
64 KiB or stateful handlers. Each call zeroes 64 KiB and each collection copies
the used bytes. The RSS of a running process was not measured.

**Rollback:** revert this change together with its callers; the step 2 encoder can
remain, since it also serves 0–32-byte outputs.
