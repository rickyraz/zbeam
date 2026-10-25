# ADR 0002 — Bounded monitorable worker lifecycle

**Status:** accepted for the M1 development profile.
**Date:** 2026-10-25.

## Decision and scope

`serve-worker` is a new explicit profile; existing echo/SHA-256 contracts remain
unchanged. One native SHA-256 worker lives for the service lifetime, independent
of sequential TCP connections. The discovery endpoint `zbeam_worker` belongs to
the service, not the worker. No general scheduler or task-owning `Runtime(T).spawn`
is introduced. The research two-worker ADR is not promoted as a public API.

## Identity and lifecycle

The worker transitions `starting -> running -> stopping -> stopped`. A failed
start publishes no identity. Normal stop removes the live worker before draining
monitor notifications, and always ends in `stopped`, including failed writes.
There is no in-process replacement in M1. The discovery endpoint remains available
and reports `noproc` after stop; the node can still handle ticks and dead-PID
monitor requests. The external owner replaces the OS process for a fresh worker.

A PID uses the registered node name and EPMD creation plus a freshly randomized
64-bit ID/serial pair per service startup. TCP reconnect preserves the PID but
not connection-scoped monitors. PID equality includes every field; stale/foreign
PID sends are discarded according to ordinary SEND semantics. A live service
never reuses its identity. Cross-process uniqueness relies on EPMD incarnation
and cryptographic randomness, not persistent allocation: loss/reuse of EPMD state
has a residual collision risk and is not an absolute uniqueness guarantee.

## Requests and outcomes

Discovery uses registered send to `zbeam_worker`: `{FromPid, Ref, discover}`.
PID-directed work is `{FromPid, Ref, {hash, Binary}}`; normal shutdown is
`{FromPid, Ref, stop}`. Replies are `{Ref, {ok, Pid}}`, `{Ref, {ok, Digest}}`,
`{Ref, ok}` or `{Ref, {error, ReasonAtom}}`. Malformed wire controls close the peer;
recognized requests with invalid arguments fail with a bounded atom reason.
Only normal stop is exposed: no production panic/OOM/spin injection endpoint.

The reply PID and request reference must originate on the authenticated peer.
The sender field of REG_SEND must match the envelope. SEND has no authenticated
sender field; a trusted cookie peer can address any of its own processes. Cookies
are node-level trust, not per-process authorization. Work input is capped at
1 MiB, frames at 2 MiB, with one synchronous operation outstanding and no queue.

## Memory and lifetime

The service owns worker identity/state. Each authenticated connection owns its
peer name and fixed monitor table. At most 64 monitors retain fixed PID/reference
integers and canonical node-name slices owned by that connection/service, never
slices from a decoded packet. Packet, decoded terms and each encoded output have
one explicit allocator owner and are released on success/error/cancellation.
A timeout task is canceled and joined before those values or names are destroyed.
The monitor table is cleared before freeing the authenticated peer name.

There is no retained message queue or variable-sized worker state. Existing
mailboxes remain caller-owned and do not recursively destroy nested allocations.
Any later task-owning runtime must separately specify close/drain/join ordering.

## Monitors and failure boundary

PID and named process monitoring are advertised together. OTP's
`erts_dsig_send_monitor` requires both bits even for PID monitoring; the original
PID-only proposal was corrected after real OTP tests exposed connection-only
fallback. The `zbeam_worker` name identifies the discovery endpoint, which remains
live after worker stop; unknown names produce `noproc`. Only the endpoint's
canonical static name may be retained. Normal worker stop notifies PID monitors,
not discovery-name monitors. Both share the fixed 64-slot connection table.
Atom caches, exit-payload controls, links and SEND_SENDER remain disabled.
Wire controls use MONITOR_P (19),
DEMONITOR_P (20) and MONITOR_P_EXIT (21) from the OTP distribution source matrix.
References use bounded NEWER_REFERENCE_EXT; legacy NEW_REFERENCE_EXT is accepted
within its documented bit/length constraints. No outbound monitor API exists;
a validated unsolicited MONITOR_P_EXIT has no local subscription to complete.

For a live target, duplicate identical monitor operations are idempotent. A
conflicting reuse of a live reference is a protocol error. Unknown/stopped PIDs
produce `noproc`; normal worker stop produces one `normal` notification per
established worker-PID monitor. Demonitor removes only a matching subscription. Notification
writes are bounded; failure closes the connection rather than claiming delivery.
Table exhaustion closes the connection, allowing OTP's connection-loss semantics
instead of silently ignoring a monitor. Disconnect clears every subscription;
there is no monitor or notification replay on a fresh connection.

Shared-stream ordering is sequential. Positive demand is reserved before every
frame, including control frames, and restored after processing/writing. Controls
can be delayed by work; no heartbeat-prefetch exemption exists. A nonreturning
native handler can require external process termination. Panic/corruption can
kill the entire native node, not just this logical worker.

## Verification and rollback boundary

Codec tests cover bounds, malformed/truncated references, cleanup and OTP vectors.
Runtime tests cover discovery, PID equality, normal/dead/stale destinations,
duplicate/demonitor/exit/table-full behavior and allocation failures. Real OTP
25/26/27 tests check exact `DOWN` reference/PID/reason and absence of duplicates,
worker exit with node survival, reconnect and new-process identity.

External-owner tests distinguish controlled stop, process/connection/EPMD loss,
request timeout and test-only panic/OOM/spin. Uncertain work fails without replay;
fresh work must use fresh identity/correlation. Tests kill only owned children.
Owner/VM death requires an independently verified process-tree cleanup boundary;
normal `terminate` callbacks alone do not prove it.

Remove the new profile/runtime handler and its flags to roll back the feature;
reference codec support remains independently usable. No changes to the battery
DAG, global compiler installation or existing service wire replies are required.
