# Internal reservation primitive — M2b prerequisite

This work unit adds a reservation state to the existing internal per-actor
admission ledger. It does **not** expose a network service, a multi-slot atomic
reservation, a lease API or a new `TaskRuntime` method. M2b remains gated by
[ADR 0005](../../adr/0005-two-worker-wire-profile.md).

The lifecycle mutex remains the caller's responsibility. A reservation occupies
one queue position and one completion ticket without allocating payload storage.
An owned reservation must be released, or transferred to a copied/queued message;
failed copy retains the reservation until its owner explicitly releases it.
`copy` retains its existing external behavior by releasing on failure. Queue
capacity counts both reserved and queued records; completion tickets remain held
until result collection or post-join discard. No hidden waiting putter is added.

Unit regressions cover full reserved capacity, zero allocation on rejection,
release/reuse, copy OOM and oversize while reserved, deep-copy mutation and exact
allocation cleanup. Existing local task lifecycle/stress tests still run.
The primitive alone cannot reserve both actors atomically, handle stop/read races,
hold output tokens or authorize a socket read. A future adapter must implement
and test those separately under a shared lifecycle gate.

Linux x86-64 WSL2, Zig 0.17.0: core/labs/lifecycle commands below completed in
both modes with **69/69 steps, 80/82 newly executed tests passed, two conditional
skips**; unaffected steps were cached. Separate subprocess watchdog and local
three-digest example passed in both modes. Full raw logs are retained beside this
record. No OTP wire change or M2b interoperability is claimed.

```sh
ZIG_LOCAL_CACHE_DIR=.zig-cache/0.17 zig build test-all test-labs test-task-lifecycle -Doptimize=debug -j2 --summary all
ZIG_LOCAL_CACHE_DIR=.zig-cache/0.17-safe zig build test-all test-labs test-task-lifecycle -Doptimize=safe -j2 --summary all
```

Rollback removes the reserved stage and its tests, returning `copy` to direct
single-actor reservation; no public exports, protocol, transport or wire behavior
need removal. The accepted M2a ownership and completion contracts remain intact.
