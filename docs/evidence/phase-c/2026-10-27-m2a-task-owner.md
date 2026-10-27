# M2a task owner: basic lifecycle, acceptance pending

`TaskRuntime` adds two fixed local SHA-256 tasks, stable storage, copied names,
transactional admission and per-slot Futures. Both tasks wait behind startup
readiness; constructor failure stops/joins every started task before destruction.
Stop removes routing under the admission mutex. Shutdown stops both first, joins
all Futures and drains queued payloads; deinit refuses before joins. The caller
must still join its external API users. M1 and `Runtime(T)` are unchanged.

Linux x86-64 WSL2 / Zig 0.17.0, PR #8 base `7d927d7`:

- `test-all test-labs` debug/safe: each 63/63 steps, 59/59 newly executed tests;
  unaffected runs cached. Independent runtime import performs real owned work.
- Focused owner binaries: 100 fresh launches per mode. Exact digests from both
  tasks, copied names, stale-ID rejection, premature deinit and repeated joins
  pass; invalid names/object OOM publish no actor.
- A test-only I/O-vtable shim rejects the first or second actual `concurrent`
  call. It counts completed cancellation/joins and checks exact allocator-byte
  balance after constructor rollback. No inline-async fallback or detach exists.
- Raw focused/full summaries retained adjacent; formatting/whitespace checked.

These checks establish basic lifecycle, not the complete M2a acceptance matrix.
Deterministic send/stop interleavings, slow collector saturation, handler faults,
noncooperative spin and independent progress remain the next work unit. No new
wire capability, custom handler API, actor-local panic isolation or production
claim follows. Rollback removes the additive task owner/export/import test and
API documentation, retaining independent mailbox and ownership-ledger primitives.
