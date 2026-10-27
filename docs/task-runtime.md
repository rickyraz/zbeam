# Local task-owning runtime

`@import("zbeam-runtime").TaskRuntime` owns two fixed SHA-256 tasks and their
mailbox/input/result storage. It is additive: `Runtime(T)` remains a caller-owned
mailbox registry, and all M1 network services remain synchronous and unchanged.
[Local M2a is accepted](evidence/phase-c/2026-10-27-m2a-acceptance.md);
this is not multi-actor OTP routing.
Run `zig build example-task-runtime -Doptimize=safe` for the
[standalone example](../examples/task_runtime.zig) (also checked by the lifecycle target).

```zig
const tasks = try runtime.TaskRuntime.create(allocator, io, .{ "left", "right" });
defer tasks.deinit() catch unreachable;
defer _ = tasks.shutdown();
const request = try tasks.trySend(tasks.whereis("left").?, "abc");
const result = (try tasks.nextResult()).?;
// Correlate result.request_id with request; inspect result.outcome.
```

Names are copied, distinct and 1–64 bytes. Local actor IDs are 1/2, meaningful only
with this live instance, never wire PIDs. `trySend` copies up to 1 MiB and returns
`WouldBlock` at four queued or five outstanding requests per actor; completed
results hold admission tickets until collected. No capacity-waiting sender task
or dynamic slot replacement is created. Payload copies total at most 10 MiB;
metadata, provider/task resources and caller-owned buffers are additional.

One collector calls `nextResult`, returning inline digest/stopped/canceled
outcomes (test-only handler faults also report `handler_failed`); null means all
tasks joined and results exhausted. `requestStop` is thread-safe with send while
the owner keeps storage alive. The single lifecycle
owner uses `stopAndJoin` for one actor or `shutdown` for both. Stop prevents new
handler claims, not effects of already accepted work; digest can win a stop race.
Shutdown closes both admissions before joining either and drains queued payloads.
`deinit` refuses `NotJoined`; callers must also join **their own API users** before
actual destruction. A future's cooperative cancel is a join, not CPU preemption.
No hard in-process shutdown deadline, actor-local panic isolation or replay is
promised. `zig build test-task-lifecycle -Doptimize=safe` runs the Linux
lifecycle/watchdog harness (repeat with `-Doptimize=debug`); conditional spin skips in ordinary unit runs are
not counted as passing the separately executed kill/reap probe.
See [ADR 0004](adr/0004-bounded-task-owned-runtime.md) and the
[M2 work plan](m2-task-lifecycle-plan.md) for executed local gates and the
separately gated M2b wire expansion. Supported methods expose IDs/results, not
mailbox handles; Zig does not statically prevent direct field/slice misuse.
