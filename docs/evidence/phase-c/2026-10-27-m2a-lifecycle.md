# M2a deterministic lifecycle and conservation

Seven new lifecycle scenarios exercise the integrated two-task runtime, not the
caller-owned admission research. Pauses/failure hooks exist only when
`builtin.is_test`; production has no configurable handler, fault switch or pause
endpoint. Every dequeued payload installs cleanup before a test checkpoint;
cancellation before claim still claims/finalizes it under the lifecycle gate.

Linux x86-64 WSL2 / Zig 0.17.0, task-owner merge base `5317bde`:

- Core/labs debug/safe each 63/63 steps, 67/67 newly executed tests;
  unaffected runs cached. Production executable build: 5/5 steps.
- 100 fresh focused launches per mode: 14/14 checks each, 2,800 total checks,
  including 1,400 new lifecycle scenarios and 20,000 exact sibling digests.
- Barriers force stop after dequeue/before claim, cancellation while holding a
  dequeued payload, full queues with an active paused handler, and handler error
  before queued work. Stop-wins starts zero handlers; paused-active starts one.
- Four/five queue/ticket limits and ten completed-uncollected results reject
  without allocating. Results return capacity; deinit deliberately discards a
  retained inline result. Counted allocations balance after joined destruction.
- A real queue-mutex hold forces canceled insertion; copied input rolls back.
  Actual send OOM restores admission; request-ID exhaustion never wraps. Failed
  actor exit is retained, queued work discarded, sibling progress preserved.
- Complete raw build/focused/repetition logs retained adjacent. No sleeps choose
  interleavings; timeout/deadline checks bound failed tests, not prove progress.

M2a acceptance still requires the noncooperative subprocess watchdog and final
integrated OTP/owner regressions. No ASan/TSan, native-host soak, performance or
M2b wire claim follows. Rollback removes test hooks/checkpoints and these tests;
the already-delivered basic task owner and prior admission primitives remain.
