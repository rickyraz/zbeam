# Internal two-worker monitor table — M2b prerequisite

This adds an internal 64-entry connection-owned table for a proposed two-worker
profile. It is **not** used by `serve-worker`, any socket, or any public API.
Both actor PIDs and the proposed discovery endpoint share one bounded table.
The connection owner serializes access and keeps peer/service node names alive.
Authenticated caller validation and negotiation of both monitor flags remain the
responsibility of the future connection dispatcher.

Matching subscriptions are idempotent; conflicting reference reuse is an error;
exact demonitor removes a subscription. Unknown names/stopped PIDs return an
immediate `noproc` request while the decoded control is alive. Live subscriptions
canonicalize peer/service node slices before retaining them. `takeExit` removes
one matching PID subscription before a future writer attempts its notification;
the other actor and discovery-name subscriptions remain untouched. Table-full is
a visible error, not a silent dropped monitor. The caller must clear connection
state on output failure and never replay on reconnect.

Four unit tests cover independent actor/name lifetimes, identity/conflict/unknown
cases, frame-node mutation, full capacity and reuse. They do not establish actual
wire flags, output encoding, stop/demonitor interleavings, epoch teardown or OTP
compatibility. [ADR 0005](../../adr/0005-two-worker-wire-profile.md) remains
proposed until those integration contracts and evidence are resolved.

Linux x86-64 WSL2/Zig 0.17.0: debug/safe core/labs/lifecycle each completed
69/69 steps, 94/96 newly executed tests passed, two conditional skips, with
unaffected runs cached; separate watchdog and local example passed. Runtime test
binary 30 fresh launches per mode: 43 passed, one conditional skip each time.
Raw logs are retained adjacent. Rollback removes the table/test import and this
record only; M1 behavior and public exports are unchanged.
