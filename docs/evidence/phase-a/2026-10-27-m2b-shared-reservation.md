# Internal shared-route reservation — M2b prerequisite

The runtime now has an **internal-only** single-reader lease. Under its existing
lifecycle mutex, acquisition reserves a queue position and completion ticket in
each currently running actor, rolling back all earlier reservations if any
actor is full. Local `trySend` uses the same ledgers and gate. No socket read,
output credit, wire profile or public reservation API is introduced here.

One owner must consume/release the lease exactly once and join its API users
before runtime deinit; copying or concurrent use of a lease is unsupported.
On stop, the runtime retires that actor's reserved tickets under the same mutex;
the lease can still commit to a running sibling or release remaining tickets.
`send` consumes the lease even on error. Copy and queue insertion remain under the
lifecycle gate; successful insertion transfers the payload, while cancellation,
OOM, invalid/stopped destination or exhausted ID rolls all reservations back.
Shutdown may join both actors with a lease held; its owner must subsequently
release the lease before deinit. Stop does not preempt a noncooperative task.

Seven tests cover all-route rollback when actor B is full, held reservation versus
local sends, copied selected request, actor-stop/sibling progress, shutdown with
a lease, allocation failure and canceled insertion with exact allocation cleanup.
They do not establish a network-read/no-read oracle, output bounds, connection
epoch, monitor semantics or OTP compatibility.

Linux x86-64 WSL2 and Zig 0.17.0: debug/safe core/labs/lifecycle each reported
**69/69 steps, 87/89 newly executed tests passed, two conditional skips**, with
unaffected runs cached. The standalone watchdog and three-digest example passed
in both modes. The runtime test binary was launched 50 fresh times per mode:
**36 passed, one conditional skip** each time, including all seven new tests.
Raw outputs are retained alongside. Local interleavings and short repetitions
are not a proof of unbounded liveness or production safety.

Rollback removes `wire_admission.zig`, its test import, the reserved-lease flag
and stop-time reservation release; the independent per-actor primitive from
PR #16 and public M2a API remain. [ADR 0005](../../adr/0005-two-worker-wire-profile.md)
continues to gate output, read integration, connection/monitor semantics and
real OTP acceptance.
