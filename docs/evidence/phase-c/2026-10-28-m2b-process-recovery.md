# Two-worker process-loss and EPMD checks — 2026-10-28

The Linux test owns a guardian and one non-forking two-worker child. It verifies
that an externally orchestrated replacement starts with fresh identities and
fresh work, without replaying an uncertain request. The test is a bounded
recovery example, not a reusable OTP supervisor or an exactly-once guarantee.

## Checks

- With the actual `serve-workers` executable, discover both workers, stop the
  owned native process with SIGSTOP and observe its stopped proc state, then
  send one request and SIGKILL the process. The test observes `nodedown`, both
  `noconnection` monitors and the guardian exit; it launches a fresh peer, checks
  distinct PIDs and two exact fresh digests, and rejects a stale old-reference
  reply. Sending while SIGSTOPped is an **uncertain** request, not proof the
  native runtime accepted it. The original BEAM OS PID and an unrelated local
  process remain responsive. Owned children and guardians are checked terminal.
- A test-only launcher registers the real two-worker node against an owned
  private EPMD port and uses the same registration-loss select pattern. Killing
  that private daemon yields node-down and joins the guarded process. Production
  CLI uses the default EPMD port; this fixture does not claim a configurable
  production port. Shared developer EPMD is never killed.
- Zig 0.17.0 on Linux/WSL, Elixir 1.20.4/OTP 29: debug and safe
  `zig build test-all test-labs test-task-lifecycle test-worker-recovery -j2
  --summary all` each passed 73/73 steps; 35/36 newly executed Zig tests, one
  conditional skip, with remaining tests cached. M1 recovery was 13 ordinary
  and one private-EPMD case per mode; the M2 campaign and proc oracle each passed
  in ordinary and private-EPMD VMs. The separate spin watchdog killed/reaped its
  child. Twenty additional fresh M2 campaigns per mode passed after correction.
- The initial safe repetition failed at campaign 4 because `/proc/<pid>/stat`
  returned `ESRCH` during disappearance. The oracle now treats only ENOENT and
  ESRCH as absent, parses after the final `) `, recognizes Z/X/x as terminal,
  and still fails on permission/malformed data. A deterministic oracle test and
  the original failure log are retained. No runtime bug is inferred from it.

## Scope and rollback

No production fault switch, in-process preemption, automatic replay, persistent
uniqueness, TLS or process-tree supervisor is added. Remove the two-worker test,
script, test-only fixture mode and build hook to roll back. Release acceptance
still requires the integrated actual-master matrix and preservation audit.
