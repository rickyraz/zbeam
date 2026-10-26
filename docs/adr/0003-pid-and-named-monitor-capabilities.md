# ADR 0003 — Negotiate PID and named monitor capabilities together

**Status:** accepted for the M1 development profile.
**Date:** 2026-10-25.
**Supersedes:** [ADR 0002](0002-monitorable-worker-lifecycle.md). Its identity,
ownership, lifecycle, request, demand and external-recovery rules are retained
except for the monitor-capability/name-lifetime rules replaced below.

## Context

Real OTP monitor tests failed under ADR 0002's PID-only negotiation: no MONITOR_P
arrived and the subscription observed only connection loss. OTP 27
[`erts_dsig_send_monitor` in dist.c](https://github.com/erlang/otp/blob/OTP-27.3.4.19/erts/emulator/beam/dist.c)
checks `~ctx->dflags & (DFLAG_DIST_MONITOR | DFLAG_DIST_MONITOR_NAME)` and falls
back to connection supervision if either bit is absent. Demonitor and monitor-exit
send functions use the same condition. Merely enabling the named bit without its
wire/lifecycle semantics would be a false capability claim.

## Decision

Only the explicit `serve-worker` profile negotiates both PID and named process
monitor bits. MONITOR_P/DEMONITOR_P accept a PID watcher and PID/atom target;
MONITOR_P_EXIT reverses their positions and carries the reason. Optional
payload-exit controls, links, caches and SEND_SENDER remain disabled.

The only registered service name is `zbeam_worker`. It denotes the service-owned
discovery endpoint, not the worker PID returned by discovery. It remains live
after worker stop. Unknown names and unknown/stopped worker PIDs produce `noproc`.
Normal worker stop emits one `normal` exit per established worker-PID monitor;
it does not notify or remove discovery-name subscriptions. Demonitor removes
only an exact watcher/reference/target match; conflicting reference reuse fails.

All target forms share the fixed 64-slot connection table. Stored names are only
the canonical static endpoint name; retained watcher/reference node slices belong
to the authenticated connection, and PID targets use service-owned node storage.
No decoded packet slices escape. Disconnect clears the table before destroying
peer storage. A failed output clears connection state, never fabricates delivery
or replays a notification on reconnect. No outbound monitor API is introduced.

## Consequences and evidence

The profile has a broader but explicit capability surface than the initial
PID-only proposal. It is still not a complete ETF/OTP node, native scheduler or
supervision tree. Existing echo/SHA-256 profiles keep their original flags.

[Wire evidence](../evidence/phase-b/2026-10-25-m1.md) and
[runtime evidence](../evidence/phase-c/2026-10-25-m1.md) record structural control
vectors, bounds/ownership/failure tests and actual OTP 25/26/27 in Debug and
ReleaseSafe. Tests distinguish PID `normal`, unknown PID/name `noproc`, disconnect
`noconnection`, named-endpoint survival, demonitor and duplicate absence.
