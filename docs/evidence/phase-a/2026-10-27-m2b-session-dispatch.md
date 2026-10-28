# Internal session dispatch — M2b prerequisite

The internal single-owner dispatcher composes the existing frame gate, request
decoder, bounded encoder, correlation credits and 64-entry monitor table. It is
not attached to a socket or exported as a service. The owner must serialize all
session operations, join its reader before handing over the frame, retain peer
and service node storage, and treat failed/partial output as connection failure.

A controlled stop retires and joins one local task, writes its stop reply, then
writes that PID's monitor exits one at a time using bounded scratch. Sibling and
discovery-name subscriptions survive. A test-only handler failure is joined,
returns `handler_failed` and emits at most one corresponding monitor exit;
queued results remain separately correlated. A result's output credit remains
held through write/drop; unknown completion fails closed. Writer timeout,
asynchronous reader/collector scheduling, epoch drain on disconnect, exact
control ordering in a live peer and real OTP compatibility remain unproven.

Three internal tests exercise a complete in-memory discovery/hash/monitor/stop
flow, sibling progress and stale-PID drop; a handler-failure monitor exit; and
failed writer/unknown completion credit cleanup. Inputs and outputs use the
project's own encoder/decoder, not independent conformance vectors or OTP.

Linux x86-64 WSL2/Zig 0.17.0: debug/safe core/labs/lifecycle each completed
69/69 steps, 109/111 newly executed tests passed with two conditional skips,
unaffected cached; standalone watchdog/example passed. Twenty fresh runtime
binary launches per mode each reported 57 passed and one conditional skip.
Complete raw logs are retained adjacent. Rollback removes the internal session,
its tests and the added failure reason; no public API or M1 wire is changed.
