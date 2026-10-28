# M2b internal connection lifetime — 2026-10-28

The internal connection loop joins its reader and result collector, releases the
held frame and drains/discards old-epoch results before peer storage can leave
scope. It accepts an already authenticated peer; no listener, CLI or new public
API is enabled. The caller must exclusively own the task runtime's admission,
collector and lifecycle during each connection and drain between epochs.

## Boundary and verification

Baseline: session PR #23, master `83d4a75`; actual-master CI
[40634233728](https://github.com/rickyraz/zbeam/actions/runs/40634233728) passed
9/9 existing-profile jobs. This is not M2b OTP acceptance.

- Zig 0.17.0, Linux/WSL, separate `.zig-cache/0.17` and `.zig-cache/0.17-safe`.
- `zig build test-all test-labs test-task-lifecycle -Doptimize=<debug|safe> -j2 --summary all`:
  69/69 steps, 114/116 newly executed tests, two conditional skips in each mode;
  other steps were cached. The separate spin watchdog actually killed/reaped
  its child; the local-runtime example also passed.
- Twenty fresh runtime-test launches per mode: each 61 passed, one spin skip.
- Socket-pair tests check two exact correlations/digests and old-epoch drainage
  before a fresh peer. These are loopback streams, not authenticated OTP sessions.
- A rejected writer launch after result collection returns its output credit;
  otherwise cleanup would wait for an already consumed completion.
- Initial regression-test setup failed with `FrameNotRead`, then `BufferedReader`.
  The corrected setup directly creates the pending result under test, without
  pretending a buffered test source is a permitted transport reader. Logs remain.

Reader/collector errors terminate the connection. Cleanup preserves non-cancellation
collector errors. Cleanup errors take precedence over the original connection
error. Deadlines cancel and join; draining accepted noncooperative work can still
wait indefinitely and requires external process kill, never early storage release.

## Remaining gates and rollback

Startup/cancellation/partial-frame/blocked-writer fault campaigns, authenticated
service integration, independent vectors and real OTP acceptance remain separate
units. Remove `wire_connection*.zig` and its test import to roll back this unit;
M1/M2a public APIs and the internal dispatcher are unchanged. Adjacent gzip logs
retain current attempts. The previous `/tmp/zbeam-m2b-20261027` ledger is absent;
new logs and recovered CI metadata are stored in a private persistent ledger.
