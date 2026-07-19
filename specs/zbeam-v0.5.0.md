# zbeam — Technical Specification

> [!IMPORTANT]
> **Design target, not implementation status.** The repository is currently a pre-alpha scaffold. Pseudocode and statements such as “implemented” or “conformance-tested” describe the proposed v0.5 design relative to earlier drafts; they are not claims about the current code. See [`docs/implementation-status.md`](../docs/implementation-status.md).

**Document Status**: Working Draft / Unimplemented Design Target
**Version**: 0.5.0-draft
**Date**: 2026-07-11
**Language**: Zig 0.16.0 (`std.Io` interface mandatory)
**Compatibility Target**: OTP 25, 26, 27 (Erlang Distribution Protocol v5/v6)
**Changes from v0.4.0**: `BufferHandle` consumed-state is now atomic CAS instead of a plain `bool` (closes the check-then-use race in `promote()`/`access()`); `SlotRefCount.release()` now panics on double-drop instead of silently underflowing, and `TransportArena.recycleSlot()` no longer double-decrements (closes the arena-leak bug); `TransportArena.acquireSlot()` claims slots via atomic CAS instead of load-then-write (closes the slot-claim race); small binaries are now copy-by-default below a configurable threshold, mirroring BEAM's heap-binary/refc-binary split, so most messages never touch the arena/refcount path at all; `Mailbox` now enforces single-owner access via an `ActorToken` capability plus a runtime owner-check; a new `ForwardOnlyHandle` type gives the common "always forward, never inspect" actor pattern static (compile-time) enforcement, closing §18.1's narrowed research question for that subset; and the node/OS-process crash-isolation boundary — true since v0.3.0 by architecture but never previously stated as a formal, tested spec invariant — is now formalized in §14.1 with conformance tests.

**Explicitly out of scope for v0.5.0** (carried forward unchanged, not touched by this revision): io_uring + `Io.Group` cancellation unification (§18.2, was v0.4 §18.2), multiparty session types for the general `BufferHandle` case (§18.3, was v0.4 §18.3), zero-copy broadcast fan-out (§17).

---

## Table of Contents

1. Abstract
2. Terminology & Conventions
3. Motivation & Prior Art
4. System Architecture
5. Module Specifications
    - 5.3 ETF — External Term Format
    - 5.5 Transport Layer
    - 5.6 Actor Runtime
6. NodeConfig & Public API
7. Node Lifecycle
8. Dist Connection Pool & Reconnect FSM
9. Wire Protocol Compliance
10. Type System & Safety Guarantees
11. Error Model
12. Memory Model
13. Concurrency Model
14. Security Model
    - 14.1 Fault Isolation & Crash Domain (NEW)
15. Integration Contracts
16. Conformance Requirements
17. Non-Goals & Explicit Exclusions
18. Research Roadmap
19. Versioning Policy
20. References

---

## 1. Abstract

zbeam is a native Zig library implementing the full Erlang Distribution Protocol (EDP v5/v6), enabling a Zig process to appear as a first-class BEAM node in an Erlang/OTP cluster — as a separate OS process speaking the wire protocol, never as a NIF, port driver, or in-process linkage of any kind.

v0.5.0 does not add new capability surface the way v0.4.0 did (promote(), io_uring, fan-out). Instead it closes correctness gaps in what v0.4.0 already shipped, and formalizes a property that was already true by construction but had never been written down as a spec invariant with tests behind it:

1. **Atomic refcount / CAS everywhere a bool or a load-then-write previously stood** — `BufferHandle.consumed`, `TransportArena.acquireSlot()`, and `SlotRefCount.release()` are rewritten around `cmpxchgStrong`/`cmpxchgWeak`. This addresses four v0.4 design defects: the `access()`/`promote()` race, concurrent double promotion, the slot-claim race, and the recycle-path double decrement. Current implementation work is tracked in [`docs/research-needed.md`](../docs/research-needed.md).
2. **Copy-by-default below a size threshold** — mirrors BEAM's own heap-binary vs. refc-binary split. Only binaries above `zero_copy_threshold` (default 64 bytes, matching BEAM's own constant) ever allocate an arena slot or touch `promote()`/`SlotRefCount` at all. This does not fix any bug by itself; it shrinks the population of messages that can ever hit the bugs in (1), which is a mitigation BEAM itself has relied on for the same reason since its refc-binary design was introduced.
3. **Single-owner execution, enforced not just documented** — `Mailbox.receive()` now requires an `ActorToken`, mintable only by `ActorRuntime.spawn()`, plus a runtime owner-check that panics on first cross-task violation instead of silently corrupting the mutex-guarded queue.
4. **`ForwardOnlyHandle`** — resolves the common-case scope narrowed in v0.4.0 §18.1. Actors that always forward a binary without inspecting it can opt into an entry point whose type has no `.access()` method at all — the mistake v0.4.0 could only catch at runtime is, for this subset, no longer expressible in the type system.
5. **§14.1 Fault Isolation & Crash Domain** — the "crash = node down, not VM down" property has been true since v0.3.0's architecture (separate OS process, dist-protocol peer, not a NIF), but v0.4.0 never stated it as a numbered invariant or gave it a conformance test. v0.5.0 does both, and gives explicit operational guidance for what the BEAM-side supervision code MUST do to make "node down" actually recoverable rather than just "silently missing."

**Explicit v0.5.0 exclusions**: it does not touch io_uring (§18.2 carried forward), it does not attempt multiparty session types for the general `promote()` case (§18.3 carried forward — `ForwardOnlyHandle` closes one subset, not the general problem), and it does not change zero-copy broadcast fan-out (still out of scope, §17).

---

## 2. Terminology & Conventions

*(All terms from v0.3.0 §2 and v0.4.0 §2 remain. New terms:)*

| Term | Definition |
|---|---|
| **ActorToken** | Opaque capability minted exactly once per actor task by `ActorRuntime.spawn()`. Required to call `Mailbox.receive()`/`receiveForward()`. Proves the caller went through the runtime's normal spawn path rather than being handed a `*Mailbox` pointer some other way. |
| **ForwardOnlyHandle** | A `BufferHandle` wrapper with no `.access()` method — only `.forward()`, which internally calls `promote()`. Used by `Mailbox.receiveForward()` for actors that never need to read a binary before relaying it. |
| **zero_copy_threshold** | Size in bytes below which an incoming binary is always deep-copied into a plain owned slice (`Term.binary`) rather than arena-backed (`Term.binary_ref`). Default 64, matching BEAM's heap-binary/refc-binary cutoff. |
| **Crash domain** | The set of OS processes / BEAM VMs that become unavailable as a consequence of a single fault. For zbeam this is formalized in §14.1. |

RFC 2119 key words apply throughout.

---

## 3. Motivation & Prior Art

### 3.1 Problem Statement (updated)

v0.4.0 implemented zero-copy actor-to-actor transfer and GenStage-native fan-out, but left three correctness gaps documented rather than closed: a check-then-use race on `BufferHandle.consumed`, an unguarded refcount decrement in the arena recycle path, and a mailbox single-owner invariant that existed only as a comment, not as code. Separately, the project's own README made a crash-isolation claim ("Crash = node down") that had never been written into the spec as a testable invariant.

| Problem | v0.4.0 | v0.5.0 |
|---|---|---|
| `consumed` check-then-set | Plain `bool`, non-atomic — race window | `std.atomic.Value(bool)` + `cmpxchgStrong` — race closed |
| `acquireSlot()` claim | `load()` then separate non-atomic write — race window | `cmpxchgStrong(0, 1, ...)` — claim is one instruction |
| `recycleSlot()` refcount | Double-decrements (`release()` *and* `recycleSlot()` both call `fetchSub`) — silent arena leak | `release()` decrements exactly once, with an underflow guard; `recycleSlot()` only resets slot state |
| All binaries | All go through the arena, regardless of size | Binaries below `zero_copy_threshold` bypass the arena entirely |
| Mailbox single-owner | Documented assumption, no code enforces it | `ActorToken` + runtime owner-check, panics on violation |
| promote() common-case safety | Runtime-checked only, for every call site | `ForwardOnlyHandle` gives the always-forward subset compile-time enforcement |
| Crash isolation | True by architecture, undocumented as an invariant, untested | Formal invariant in §14.1, with a conformance test that actually crashes the process and asserts on the blast radius |

### 3.2 Prior Art

The transport/protocol prior-art analysis is unchanged from v0.4.0. The atomic-CAS design follows established refcounted-runtime practice and is informed by region-based memory management (Tofte & Talpin 1997; Grossman et al., *Region-Based Memory Management in Cyclone*, PLDI 2002) and BEAM's refc-binary implementation. §20 lists the supporting references.

---

## 4. System Architecture

*(Unchanged from v0.4.0 — no structural change to the transport/actor diagram.)*

### 4.1 Design Invariants

*(Invariants 1–7 from v0.3.0/v0.4.0 unchanged. New invariants:)*

8. **Every check-then-act sequence on shared state MUST be a single atomic RMW instruction, not a load followed by a separate write.** This is now a conformance requirement (§16), not just a style preference — v0.4.0's `acquireSlot()` and `BufferHandle.promote()` violated it; v0.5.0 does not.
9. **A `Mailbox` MUST only ever be read by the task that owns it.** This was previously an assumption; as of v0.5.0 it is checked at runtime via `ActorToken` + owner-id comparison, panicking on the first violation rather than silently corrupting the queue.
10. **A fault inside the zbeam process MUST NOT be observable by the connected BEAM VM as anything other than a distribution-protocol disconnect.** See §14.1. This invariant was true since v0.3.0's choice of architecture; v0.5.0 is the first version to state it as a numbered invariant with a conformance test.

---

## 5. Module Specifications

### 5.3 ETF — External Term Format

#### 5.3.1 BufferHandle — Atomic Consumed State (rewritten)

The `consumed: bool` field from v0.4.0 is replaced with `consumed: std.atomic.Value(bool)`. `promote()` and `access()` are unchanged in signature — only the internal check-then-act sequence changes, from two separate operations to one.

```zig
pub const BufferHandle = struct {
    bytes:    []const u8,
    arena_id: u32,
    slot_ref: *SlotRefCount,
    consumed: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    pub fn toOwned(self: BufferHandle, allocator: std.mem.Allocator) ![]u8 {
        return allocator.dupe(u8, self.bytes);
    }

    // v0.4.0: `if (self.consumed) @panic(...); self.consumed = true;`
    // — two separate operations, racy if ever called concurrently.
    //
    // v0.5.0: cmpxchgStrong makes "check it's false" and "set it true"
    // one indivisible instruction (LOCK CMPXCHG / LDXR+STXR at the
    // hardware level — see §13 for the mapping). A concurrent second
    // caller cannot observe `false` after the first caller has already
    // started transitioning it; it either sees the CAS fail immediately,
    // or it never gets there because the first caller's CAS already won.
    pub fn promote(self: *BufferHandle, runtime: *ActorRuntime, target: Pid) !OwnedHandle {
        if (self.consumed.cmpxchgStrong(false, true, .acq_rel, .acquire) != null) {
            @panic("BufferHandle.promote() called twice (or raced) on the same handle");
        }
        self.slot_ref.retain();
        try runtime.notifyTransfer(self.arena_id, target);
        return .{ .bytes = self.bytes, .arena_id = self.arena_id, .slot_ref = self.slot_ref };
    }

    pub fn access(self: *const BufferHandle) []const u8 {
        if (self.consumed.load(.acquire)) {
            @panic("BufferHandle accessed after promote() transferred ownership");
        }
        return self.bytes;
    }
};
```

**Closed concurrent hazard**: this design closes the *concurrent* hazard — two threads racing `promote()` against each other, or a concurrent `access()` observing a stale `false` while a `promote()` on another thread is mid-flight. It does **not** close the *same-thread logic* hazard flagged in v0.4.0 §18.1 — a handler that copies `.bytes` into a local variable and keeps using that local copy *after* calling `promote()` on the original handle is still not caught by any flag, atomic or not, because nothing about that pattern is a race; it is a single-threaded aliasing mistake, and Zig's type system has no way to invalidate a `[]const u8` that was copied out of a struct before the struct changed state. `ForwardOnlyHandle` (§5.3.2) closes this for the subset of actors that never need `.access()` at all; the general case remains open per §18.1.

#### 5.3.2 ForwardOnlyHandle — Static Enforcement for the Common Case (NEW, closes §18.1 for one subset)

v0.5.0 defines static enforcement for the unconditional “always forward, never inspect” subset identified in v0.4.0 §18.1. `ForwardOnlyHandle` removes byte-access operations from that subset's API:

```zig
// Returned only by Mailbox.receiveForward(). Deliberately has no
// .access() method — not "access() that panics," but no method with
// that name or effect exists on this type at all. A handler written
// against ForwardTerm cannot read `.bytes` before forwarding, because
// there is no code path through the type checker that would let it.
// This is Zig's normal "the method isn't there" compile error, not a
// runtime safety net.
pub const ForwardOnlyHandle = struct {
    inner: BufferHandle,

    pub fn forward(self: ForwardOnlyHandle, runtime: *ActorRuntime, target: Pid) !OwnedHandle {
        var handle = self.inner;
        return handle.promote(runtime, target);
    }
};

pub const ForwardTerm = union(enum) {
    integer: i64,
    float:   f64,
    atom:    Atom,
    binary:  []const u8,             // copy-by-default, see §5.3.3 — never arena-backed
    binary_ref: ForwardOnlyHandle,   // arena-backed, forward-only
    pid:     RawPid,
    ref:     RawRef,
    tuple:   []ForwardTerm,
    list:    []ForwardTerm,
    map:     []KV,
    nil,
    boolean: bool,

    pub const KV = struct { key: ForwardTerm, value: ForwardTerm };
};
```

**Scope, stated honestly**: this closes the mistake for actors written against `receiveForward()`. It changes nothing for actors written against the general-purpose `receive()`, which still returns a `Term` with a full, both-methods-available `BufferHandle` for the (legitimate) cases where an actor must inspect a binary and then *conditionally* decide whether to forward it, copy it, or drop it. That conditional case is exactly the one v0.4.0 §18.1 already showed cannot be resolved by `comptime` — it remains runtime-checked via §5.3.1's atomic CAS, same as v0.4.0, just race-free now instead of merely UB-adjacent.

#### 5.3.3 Copy-by-Default Threshold (NEW)

The ETF decoder now decides, per binary, whether to deep-copy immediately or arena-back it, based on a configurable size threshold — the same split BEAM's own runtime makes internally between heap binaries and refc binaries.

```zig
pub fn decodeBinary(
    allocator: std.mem.Allocator,
    arena: *TransportArena,
    raw: []const u8,
    threshold: u32,
) !Term {
    if (raw.len < threshold) {
        // Below threshold: always copy. No arena slot is ever allocated
        // for this payload, so none of §5.3.1's machinery — the atomic
        // consumed flag, SlotRefCount, promote()/access() — is ever
        // reachable for it. There is nothing to race on because there
        // is no shared, mutable, multiply-referenced state involved.
        const copy = try allocator.dupe(u8, raw);
        return .{ .binary = copy };
    }
    const slot = try arena.wrapIncoming(raw);
    return .{ .binary_ref = BufferHandle{
        .bytes = slot.bytes,
        .arena_id = slot.id,
        .slot_ref = &arena.refs[slot.id],
    } };
}
```

`Term` (§5.3.1 of v0.4.0) gains the plain-copy variant alongside the existing arena-backed ones:

```zig
pub const Term = union(enum) {
    integer: i64,
    float:   f64,
    atom:    Atom,
    binary:      []const u8,     // NEW default path — copy-by-default, below threshold
    binary_ref:  BufferHandle,   // above threshold — arena-backed, promote()-able
    binary_owned: OwnedHandle,   // result of promote() — safe to hold indefinitely
    pid:     RawPid,
    ref:     RawRef,
    tuple:   []Term,
    list:    []Term,
    map:     []KV,
    nil,
    boolean: bool,

    pub const KV = struct { key: Term, value: Term };
};
```

**Mitigation scope and rationale**: the threshold does not make `promote()` safer for large binaries — those still go through the exact machinery in §5.3.1. The mitigation removes the *default* case (small binaries, which dominate most message traffic in practice — control messages, small tuples, short atoms-as-binaries) from ever touching that machinery at all. BEAM made the identical trade for the identical reason: refc binaries exist because copying is fine at small sizes and wasteful at large ones, not because copying is unsafe. §13 discusses why "copy small, refcount large" is the same shape of argument BEAM's own C runtime makes.

*(§5.3.4–5.3.6, formerly v0.4.0 §5.3.3–5.3.5, unchanged.)*

---

### 5.5 Transport Layer

#### 5.5.1 Buffer Arena — Atomic Claim, Fixed Recycle (rewritten)

Three changes: `SlotRefCount.release()` gains an underflow guard (panics instead of silently corrupting), `recycleSlot()` no longer touches the refcount at all, and `acquireSlot()` claims a slot via CAS instead of load-then-write.

```zig
pub const SlotRefCount = struct {
    count: std.atomic.Value(u32),

    // A freshly claimed slot starts at 1 — the claimer is the first owner.
    pub fn init() SlotRefCount {
        return .{ .count = std.atomic.Value(u32).init(1) };
    }

    // A recycled slot goes back to 0 — free, claimable by acquireSlot's
    // CAS. This is the ONLY place a slot's refcount is set to 0 by
    // anything other than release() itself reaching 0 through decrement.
    pub fn initFree() SlotRefCount {
        return .{ .count = std.atomic.Value(u32).init(0) };
    }

    pub fn retain(self: *SlotRefCount) void {
        _ = self.count.fetchAdd(1, .acq_rel);
    }

    // v0.4.0: plain fetchSub, no guard. If release() is ever called
    // twice on the same handle (the double-drop bug documented in
    // v0.4.0 §10.3 as "not caught"), the second call would underflow a
    // u32 to 4294967295, and TransportArena.recycleSlot()'s OWN
    // fetchSub made this worse by decrementing a second time on the
    // same drop, guaranteeing the slot could never again read as 0 —
    // a permanent leak.
    //
    // v0.5.0: release() is the ONLY place count is decremented. A
    // double-drop is now impossible to miss — it panics immediately
    // instead of silently corrupting a counter that only manifests as
    // a leak much later, far from the call site that caused it.
    pub fn release(self: *SlotRefCount) bool {
        var current = self.count.load(.acquire);
        while (true) {
            if (current == 0) {
                @panic("SlotRefCount.release(): refcount already zero — double-drop detected");
            }
            const next = current - 1;
            if (self.count.cmpxchgWeak(current, next, .acq_rel, .acquire)) |actual| {
                current = actual; // lost a race with a concurrent retain/release, retry
                continue;
            }
            return next == 0;
        }
    }
};

pub const TransportArena = struct {
    buffers:     []align(4096) u8,
    buffer_size: usize,
    count:       usize,
    next_id:     std.atomic.Value(u32),
    refs:        []SlotRefCount,

    pub fn init(allocator: std.mem.Allocator, count: usize, buffer_size: usize) !TransportArena {
        const buffers = try allocator.alignedAlloc(u8, 4096, count * buffer_size);
        const refs = try allocator.alloc(SlotRefCount, count);
        for (refs) |*r| r.* = SlotRefCount.initFree();  // arena starts empty, not "owned"
        return .{
            .buffers = buffers, .buffer_size = buffer_size,
            .count = count, .next_id = std.atomic.Value(u32).init(0),
            .refs = refs,
        };
    }

    // v0.4.0: `if (self.refs[id].count.load(.acquire) == 0) { self.refs[id]
    // = SlotRefCount.init(); ... }` — the load and the write are two
    // separate operations. Between them, another caller (in a future
    // multi-producer acquireSlot scenario, or after next_id wraps under
    // heavy contention) could observe the same id as also free and race
    // the claim.
    //
    // v0.5.0: the 0 -> 1 transition is the CAS itself. There is no
    // window between "see it's free" and "mark it taken" because those
    // are the same hardware instruction.
    pub fn acquireSlot(self: *TransportArena) !BufferSlot {
        var attempts: usize = 0;
        while (attempts < self.count) : (attempts += 1) {
            const id = self.next_id.fetchAdd(1, .monotonic) % @as(u32, @intCast(self.count));
            if (self.refs[id].count.cmpxchgStrong(0, 1, .acq_rel, .acquire) == null) {
                const start = id * self.buffer_size;
                return .{ .id = id, .bytes = self.buffers[start .. start + self.buffer_size] };
            }
        }
        return error.ArenaExhausted;
    }

    // v0.4.0: `_ = self.refs[id].count.fetchSub(1, .acq_rel);` — this
    // decremented a counter that release() had ALREADY decremented to 0,
    // underflowing it. v0.5.0: recycleSlot() is only ever called after
    // release() has already confirmed (via its return value) that the
    // count reached exactly 0. Its only job now is resetting the slot
    // back to the "free, claimable" state.
    pub fn recycleSlot(self: *TransportArena, id: u32) void {
        self.refs[id] = SlotRefCount.initFree();
    }

    // NEW: used by decodeBinary (§5.3.3) to wrap an incoming payload
    // that has already landed in a claimed slot's memory. Distinct from
    // acquireSlot: this does not itself claim a slot, it wraps one the
    // transport layer's receive path already owns.
    pub fn wrapIncoming(self: *TransportArena, slot: BufferSlot) BufferHandle {
        return .{
            .bytes = slot.bytes,
            .arena_id = slot.id,
            .slot_ref = &self.refs[slot.id],
        };
    }

    pub const BufferSlot = struct { id: u32, bytes: []u8 };
};
```

*(§5.5.2 io_uring, §5.5.3 Demand-Based Receiver, §5.5.4 Transport Layer Interface — unchanged from v0.4.0. The cancellation-leak gap in §5.5.2 is untouched by this revision; see §18.2.)*

---

### 5.6 Actor Runtime

#### 5.6.1–5.6.3

*(Unchanged from v0.4.0)*

#### 5.6.4 Single-Owner Enforcement (NEW)

`Mailbox` gains an `ActorToken` requirement on `receive()`/`receiveForward()`, plus a runtime owner-check. The token itself is the primary (compile-time-adjacent) defense: it can only be obtained from `ActorRuntime.spawn()`, so a `Mailbox` cannot be read without having gone through the normal actor-spawn path. The owner-check is the safety net for the case where a token or a raw pointer is passed to a second task anyway (nothing in Zig prevents copying a struct or sharing a pointer across threads — this is the same category of gap `consumed`/`SlotRefCount` close for buffers, applied to mailbox ownership):

```zig
pub const ActorToken = struct {
    task_id: std.Thread.Id,
    // No public constructor. The only place a value of this type is
    // ever produced is inside ActorRuntime.spawn(), immediately before
    // the new task's body runs — so possessing a token is proof the
    // holder's task_id matches a task the runtime itself created.
};

pub const Mailbox = struct {
    // ... unchanged fields from v0.3.0/v0.4.0: mutex-guarded queue,
    // DemandSignal, event ...
    owner: std.atomic.Value(?std.Thread.Id) = std.atomic.Value(?std.Thread.Id).init(null),

    pub fn receive(self: *Mailbox, io: std.Io, token: ActorToken) !Term {
        self.assertSingleOwner(token);
        return self.receiveLocked(io); // unchanged mutex+event logic from v0.3.0 §5.6.5
    }

    pub fn receiveForward(self: *Mailbox, io: std.Io, token: ActorToken) !ForwardTerm {
        self.assertSingleOwner(token);
        return self.receiveLockedForward(io); // same delivery path, ForwardTerm-typed
    }

    // First caller to reach this "claims" the mailbox for its task_id.
    // Every subsequent call from that same task_id is a normal no-op
    // check. A call from any OTHER task_id panics immediately, on the
    // first violation, rather than letting two tasks silently interleave
    // access to the same mutex-guarded queue (which would not corrupt
    // memory — the mutex still holds — but would violate the demand/
    // ordering semantics the actor model assumes, silently).
    fn assertSingleOwner(self: *Mailbox, token: ActorToken) void {
        const current = token.task_id;
        const prev = self.owner.cmpxchgStrong(null, current, .acq_rel, .acquire);
        if (prev) |actual_prev| {
            if (actual_prev != current) {
                @panic("Mailbox.receive() called from a task other than its owner — single-owner invariant violated");
            }
        }
    }
};
```

**Single-owner enforcement scope**: v0.4.0 §5.6.5 treated the v0.3.0 mutex fix as sufficient, and it is sufficient for *memory safety* — the mutex was never the problem. The previously unenforced *actor-model* invariant requires that exactly one task ever calls `receive()` on a given mailbox; a second task calling it would not corrupt the queue, but it would silently violate the demand-signal accounting in §5.6.6's `DemandCombinator` and the ordering guarantees actor code is written to assume. This closes that gap the same way the rest of v0.5.0 does: compile-time where possible (the token requirement), atomic runtime check as the fallback (the owner-id CAS).

#### 5.6.5 Actor Body & Receive — Updated Examples

```zig
fn myForwardingActor(io: std.Io, ctx: ActorContext, downstream: Pid) !void {
    ctx.mailbox.demand.grantOne();

    while (true) {
        // Uses receiveForward() + ForwardTerm: for an actor that only
        // ever relays binaries downstream, there is no .access() method
        // to misuse even by accident — the mistake v0.4.0 could only
        // catch via the `consumed` panic is not expressible here.
        var msg = try ctx.mailbox.receiveForward(io, ctx.token);

        switch (msg) {
            .binary_ref => |*handle| {
                const owned = try handle.forward(ctx.runtime, downstream);
                try ctx.send(io, downstream, .{ .binary_owned, owned });
            },
            .binary => |bytes| {
                // Below zero_copy_threshold — already an owned copy,
                // no arena, no promote() needed, just send it.
                try ctx.send(io, downstream, .{ .binary, bytes });
            },
            .stop => break,
            else => {},
        }

        ctx.mailbox.demand.grantOne();
    }
}

fn myInspectingActor(io: std.Io, ctx: ActorContext, downstream: Pid) !void {
    // This actor DOES need to look at the bytes before deciding what to
    // do — the general case v0.4.0 §18.1 says cannot be statically
    // enforced. Uses the general receive() + full BufferHandle.
    ctx.mailbox.demand.grantOne();
    while (true) {
        var msg = try ctx.mailbox.receive(io, ctx.token);
        switch (msg) {
            .binary_ref => |*handle| {
                const bytes = handle.access(); // legitimate — inspecting, not yet forwarding
                if (shouldForward(bytes)) {
                    const owned = try handle.promote(ctx.runtime, downstream);
                    try ctx.send(io, downstream, .{ .binary_owned, owned });
                }
                // else: handle drops at end of scope, arena slot recycles
                // once this actor's reference and any others reach 0.
            },
            .stop => break,
            else => {},
        }
        ctx.mailbox.demand.grantOne();
    }
}

fn myTerminalActor(io: std.Io, ctx: ActorContext) !void {
    ctx.mailbox.demand.grantOne();
    while (true) {
        const msg = try ctx.mailbox.receive(io, ctx.token);
        switch (msg) {
            .binary_owned => |owned| {
                process(owned.bytes);
                owned.drop(ctx.runtime.transport_arena); // panics loudly now if called twice
            },
            .stop => break,
            else => {},
        }
        ctx.mailbox.demand.grantOne();
    }
}
```

**Updated contract**: every received `OwnedHandle` MUST call `.drop()` exactly once. A second call produces an immediate `@panic` instead of delayed refcount corruption or an arena leak.

#### 5.6.6 Demand Combinator — Fan-Out

*(Unchanged from v0.4.0.)*

#### 5.6.7 Link & Monitor Tables

*(Unchanged from v0.4.0.)*

---

### 5.7 Name Registry / 5.8 Effect Channel

*(Unchanged from v0.4.0.)*

---

## 6. NodeConfig & Public API

```zig
pub const NodeConfig = struct {
    // --- Identity, Network, Transport Buffer Ring, Demand/Flow Control ---
    // (unchanged fields from v0.4.0 — node_name, cookie, listen_port,
    // epmd_host, epmd_port, transport_buffer_count, transport_buffer_size,
    // enable_io_uring, initial_actor_demand, fan_out_dispatch)

    // Binaries below this size are always deep-copied (Term.binary);
    // binaries at or above it are arena-backed (Term.binary_ref) and
    // eligible for promote(). Default matches BEAM's own heap-binary /
    // refc-binary cutoff — see §5.3.3 and §13.
    zero_copy_threshold: u32 = 64,   // NEW

    // --- Limits ---
    max_message_size: u32 = 134_217_728,
    max_actors:       u32 = 65_536,
    mailbox_max_depth: u32 = 0,
    max_promoted_handles: u32 = 32,

    // --- Scheduler ---
    reduction_budget: u32 = 2_000,

    // --- Reconnect ---
    reconnect_backoff_min_ms: u32 = 500,
    reconnect_backoff_max_ms: u32 = 30_000,
    reconnect_max_attempts:   u32 = 0,

    // There is deliberately no config flag to disable the single-owner
    // check or the atomic CAS paths introduced in v0.5.0. Both v0.3.0's
    // NodeConfig and v0.4.0's added an opt-out for the experimental
    // io_uring path because that gap was known-open and needed a
    // documented escape hatch; the fixes in this revision are closing
    // known bugs, not adding experimental behavior, so there is nothing
    // to opt out of.
};
```

---

## 7. Node Lifecycle

*(§7.1 startup sequence unchanged from v0.4.0, with one addition at step 5: `TransportArena.init()` now initializes every slot via `SlotRefCount.initFree()` rather than `SlotRefCount.init()` — the arena starts with zero owned slots, not `count` owned slots, correcting an implicit assumption in v0.3.0/v0.4.0 that was harmless only because nothing ever read an uninitialized slot's refcount before its first `acquireSlot()`.)*

*(§7.2, §7.3 unchanged.)*

---

## 8–9. Dist Connection Pool, Wire Protocol Compliance

*(Unchanged from v0.4.0.)*

---

## 10. Type System & Safety Guarantees

### 10.1–10.2

*(Unchanged from v0.4.0.)*

### 10.3 BufferHandle Lifetime — Current State (updated)

- Handler-scope escape via storage: caught at compile time via `HandlerScoped(T)` wrapper (v0.4.0 §5.3.2, unchanged).
- Double-promote or access-after-promote, **including concurrent calls**: caught via atomic CAS in all builds where the check compiles in (§5.3.1) — this is now race-free, not just "usually fine because it's rare."
- Access-then-forward on a handle the actor never intended to inspect: not reachable at all when the actor is written against `receiveForward()`/`ForwardOnlyHandle` (§5.3.2); still runtime-checked-only when written against the general `receive()` (unchanged from v0.4.0, by design — see §18.1).
- Double-drop or missing-drop on `OwnedHandle`: **missing-drop remains undetected** because the design does not attempt compile-time obligation checking without linear types. **Double-drop is detected** — `SlotRefCount.release()` panics on an already-zero count instead of underflowing silently (§5.5.1). This narrows the v0.4.0 §10.3 gap without making misuse statically impossible.
- `Mailbox` single-owner violation: **NEW** — caught via `ActorToken` + runtime owner-check (§5.6.4).

---

## 11. Error Model

```zig
// EpmdError, HandshakeError, DistError, EtfError, TransportError,
// FanOutError — unchanged from v0.4.0.

// No new Zig error set is introduced for the double-drop or
// single-owner violations — both are @panic, consistent with how
// v0.4.0 already treats promote()-twice and access-after-promote.
// These are programmer-error classes (violations of a documented
// contract), not recoverable runtime conditions, so they are not
// modeled as `error{}` values that calling code is expected to `catch`.
```

---

## 12. Memory Model

### 12.1 Allocator Architecture

*(Table unchanged from v0.4.0, with one addition:)*

| Tier | Allocator | Scope | Purpose |
|---|---|---|---|
| Copy-by-default | `std.mem.Allocator` (caller-supplied) | Handler-determined, ordinary Zig ownership | Binaries below `zero_copy_threshold` — never touches the arena |

### 12.2 Ownership Rules

*(Rules 1–9 from v0.3.0/v0.4.0 unchanged. New/updated rules:)*

10. Binaries below `zero_copy_threshold` are `Term.binary` — a plain owned `[]const u8` with ordinary Zig allocator semantics. No `SlotRefCount`, no `promote()`, no arena slot is ever involved for these.
11. A `Mailbox` MUST only be read via a valid `ActorToken` obtained from `ActorRuntime.spawn()`. Passing a token or a `*Mailbox` to a second task and calling `receive()` from both is a contract violation, caught at runtime (§5.6.4).
12. `SlotRefCount.release()` calling `@panic` on an already-zero count is expected, correct behavior on a double-drop — it is not a bug to be caught and suppressed; it indicates a bug at the call site that MUST be fixed there, not worked around at the `SlotRefCount` layer.

---

## 13. Concurrency Model

### 13.1–13.2

*(Unchanged from v0.4.0.)*

### 13.3 Demand Signal — Concurrency Contract

*(Unchanged from v0.4.0.)*

### 13.4 Atomic CAS — Hardware Mapping (NEW)

Every check-then-act sequence rewritten in this revision (`consumed`, `acquireSlot`, `release`) compiles to a single hardware read-modify-write instruction — `LOCK CMPXCHG` on x86-64, an `LDXR`/`STXR` retry pair on ARM — rather than two separate instructions with a gap between them. This is the same primitive BEAM's own C runtime uses for refc-binary refcounting (`erts_refc_inc`/`erts_refc_dec`, built on the compiler's `__atomic_*` builtins), and the same reasoning applies here: the hardware guarantees the read-and-write pair is indivisible from the point of view of every other core observing that memory location, which a Zig-level `if (x) { x = true; }` does not, regardless of how unlikely the interleaving seems in a given build.

This does not make every use of these primitives free — `cmpxchgWeak` in `SlotRefCount.release()` is a retry loop under contention, same cost profile as any lock-free counter. `zero_copy_threshold` (§5.3.3) is the main lever for keeping contention on `SlotRefCount`/`TransportArena` low in practice: fewer, larger arena-backed messages contend on these atomics far less than every message doing so would.

### 13.5 Task Lifecycle Rules / 13.6 Synchronization via std.Io.Event

*(Unchanged from v0.4.0. The io_uring cancellation caveat remains a known, undedicated gap — §18.2.)*

---

## 14. Security Model

*(§14 body from v0.3.0/v0.4.0 unchanged. New subsection:)*

### 14.1 Fault Isolation & Crash Domain (NEW)

This subsection formalizes a property that has been true since v0.3.0's architectural decision to implement zbeam as a distribution-protocol peer rather than a NIF, but which v0.3.0 and v0.4.0 only ever stated informally in `README.md`'s comparison table, never as a numbered spec invariant with a conformance test behind it.

**Invariant (restated from §4.1 item 10)**: a fault inside the zbeam process — a Zig `@panic`, `unreachable`, an out-of-bounds access in an unchecked build, a segfault, an allocator abort under OOM — MUST NOT be observable by the connected BEAM VM as anything other than a distribution-protocol disconnect (`nodedown`). This is not a code path zbeam implements; it is a consequence of zbeam always being a separate OS process communicating over TCP via EDP, and it holds regardless of which bug in zbeam's own code caused the fault.

**Comparison, formalized from README**:

| Approach            | Identity                | Crash-time coupling                          | BEAM VM observation                                                                                                                                   |
| ------------------- | ----------------------- | -------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| NIF (e.g. Zigler)   | None — in-process       | Shares the BEAM OS process and address space | The entire VM terminates — every process on that node, related or not                                                                                       |
| Port driver         | Port id                 | Shares the BEAM OS process                   | The VM may survive, but the driver's internal state and the port are gone; historically a common source of full-VM crashes too, depending on driver quality |
| Port (stdin/stdout) | Port id                 | Separate OS process                          | Port closes; VM continues; other processes on the VM are unaffected                                                                                         |
| **zbeam**           | Full BEAM node identity | Separate OS process, TCP peer                | `nodedown` via distribution protocol monitoring; VM continues; other processes and other connected nodes are unaffected                                     |

**v0.5.0 mechanism impact**: no mechanism changes at this boundary — the process boundary already existed in v0.3.0. v0.5.0 adds the following specification and verification requirements:
1. A numbered invariant (§4.1 item 10) instead of only a README claim.
2. Conformance-tested (§16) by actually crashing a zbeam process under test and asserting on the blast radius, rather than being an assumption nobody had written an assertion for.
3. Paired with an explicit operational contract (below) for what the BEAM-side supervision code MUST do, because "the VM survives" and "the failure is handled" are not the same claim, and only the first one is true for free.

**Deployment responsibility**: zbeam is a distribution peer and does not supervise its own OS process (§17). A crash produces `nodedown` only for connected BEAM nodes that monitor node events. Production deployments therefore MUST enable node monitoring and pair zbeam with an external process supervisor:

```elixir
# Minimum viable supervision on the Elixir/Erlang side — this is NOT
# something zbeam can do on its own, because zbeam is the thing that
# might be down, not the thing watching for it.
:net_kernel.monitor_nodes(true)

def handle_info({:nodedown, node}, state) do
  # restart / reconnect logic, alerting, circuit-breaking, etc.
  # zbeam's reconnect FSM (§8) handles the wire-level reconnection once
  # the process is back; this callback is what notices it went away
  # and, if the OS process itself died, is responsible for restarting
  # THAT (e.g. via an OS-level supervisor — systemd Restart=on-failure,
  # or an OTP-supervised Port wrapping the zbeam binary).
end
```

**Remaining limitation**: this section does not reduce the zbeam process crash rate to zero. §5.3.1, §5.5.1, and §5.6.4's fixes reduce how often zbeam's own process crashes due to the specific bug classes they target (races, double-drops, single-owner violations) — this is defense in depth, not a claim that zbeam cannot crash. Zig is not a memory-safe-by-default language; `ReleaseFast` builds compile out the safety checks this entire spec relies on (§4.1 item 7, unchanged since v0.4.0), and nothing in v0.5.0 changes that trade-off. The claim this section makes is narrower and, unlike memory safety, is actually total: *when* zbeam crashes, for any reason, the blast radius stops at the process boundary. It does not claim zbeam crashes less often than any other native code would — v0.5.0's other sections are what work on that, incrementally and partially, same as any real system.

---

## 15. Integration Contracts

*(Unchanged from v0.4.0, with the supervision snippet from §14.1 added as a required — not optional — integration step for production deployments.)*

---

## 16. Conformance Requirements

| Category | Tests | Tooling |
|---|---|---|
| All v0.3.0/v0.4.0 categories | ... | ... |
| **Atomic consumed state** | 1000-iteration concurrent-promote stress test on the same handle from two tasks — exactly one succeeds, the other panics deterministically, never both succeed | TSAN / Zig sanitizers + custom harness |
| **acquireSlot race** | N tasks racing `acquireSlot()` against an arena with fewer than N free slots — no two tasks ever receive the same `arena_id` | Custom concurrency harness |
| **recycleSlot no double-decrement** | `promote()` → `drop()` → assert slot refcount is exactly 0, not underflowed; deliberately call `drop()` twice on a cloned `OwnedHandle` and assert `@panic`, not silent leak | Custom harness (panic-catching) |
| **Mailbox single-owner** | Second task calling `receive()` on a mailbox already owned by another task panics on first call, not eventually / not silently | Custom harness (panic-catching) |
| **ForwardOnlyHandle compile-time check** | A test file attempting `.access()` on a `ForwardOnlyHandle` MUST fail to compile — verified via `zig build` expecting non-zero exit, not a runtime assertion | Build-matrix CI |
| **Copy-by-default threshold** | Binaries at `threshold - 1` bytes produce `Term.binary` (owned, no arena); binaries at `threshold` bytes produce `Term.binary_ref` (arena-backed); boundary is exact, not off-by-one | Elixir ExUnit round-trip |
| **§14.1 crash isolation (NEW)** | Spawn a zbeam node as a child OS process from a test harness; deliver a crafted message engineered to trigger a deliberate `@panic` inside the zbeam process; assert (a) the local BEAM VM's own `os:getpid()` is unchanged and it is still responsive, (b) an unrelated, independently-spawned local Elixir process is still alive and responsive throughout, (c) `:net_kernel` delivers `{:nodedown, node}` within a bounded time window | External test harness spawning a real OS process + fault injection, run outside the normal ExUnit sandbox |

**Explicitly not required for v0.5.0 conformance** (carried forward, unchanged reasons): io_uring cancellation leak-freedom (§5.5.2, §18.2) and general-case (non-`ForwardOnlyHandle`) static enforcement of promote()-once semantics (§18.3) remain open; conformance tests verify the documented fallback/runtime-check behavior, not that the underlying gap is closed.

---

## 17. Non-Goals & Explicit Exclusions

*(All v0.4.0 non-goals remain except where narrowed below. Updates:)*

- **Compile-time enforcement of `OwnedHandle.drop()` in the general case** — still a non-goal; v0.5.0 upgrades the *failure mode* of a double-drop from silent refcount corruption to an immediate panic (§5.5.1), but does not statically prevent the mistake. Full closure still needs linear/session types (§18.3).
- **Static enforcement of `promote()`-once for the general (conditional) case** — still a non-goal; `ForwardOnlyHandle` (§5.3.2) closes only the unconditional-forward subset.
- **Zero-copy broadcast fan-out** — unchanged non-goal from v0.4.0.
- **Full io_uring + `Io.Group` cancellation safety** — unchanged non-goal from v0.4.0; not touched by this revision at all.
- **Reducing zbeam's own internal crash rate to zero** — explicitly out of scope; §14.1 is about *bounding the blast radius* of a crash, not eliminating the possibility of one. Conflating these two claims is exactly the mistake this spec is trying not to make (see §14.1's closing paragraph).

---

## 18. Research Roadmap (carried forward, narrowed further)

### 18.1 Full Linear-Type Enforcement of `promote()`/`drop()` — narrowed again

`ForwardOnlyHandle` (§5.3.2) provides static enforcement for unconditional forwarding. The conditional case (`if (should_forward) handle.promote(...) else handle.access(...)`) remains unresolved because it depends on a runtime branch beyond Zig `comptime` analysis. Full linear types or multiparty session types remain candidate approaches (§18.3).

### 18.2 io_uring + Io.Group Cancellation Unification (unchanged from v0.4.0)

Not touched by this revision. Still open, still bounded by the fallback described in v0.4.0 §5.5.2.

### 18.3 Multiparty Session Types for Full BufferHandle Lifecycle (unchanged scope, renumbered from v0.4.0 §18.3)

Unchanged from v0.4.0. `ForwardOnlyHandle` is a narrow, ad-hoc closure of one subset of this problem via ordinary Zig types, not a step toward the general session-type machinery in [9]/[10] — that remains a separate, larger effort.

### 18.4 Arena Partitioning per Scheduler Thread (NEW research item, not attempted in v0.5.0)

§4.1 item 9 and §5.6.4 enforce single-owner access to a `Mailbox` at the actor level, but `TransportArena` remains shared by tasks that call `acquireSlot()` or `recycleSlot()`. The CAS-based fixes in §5.5.1 provide correctness, not contention freedom. A future revision MAY evaluate per-`Io.Group`-worker arena partitions, similar to BEAM scheduler-local allocator carriers, against the simpler `zero_copy_threshold` approach (§5.3.3).

---

## 19. Versioning Policy

*(Unchanged from v0.4.0.)*

**Minimum Zig version: 0.16.0**

---

## 20. References

*(All references from v0.3.0/v0.4.0 unchanged and retain their original numbering. Added in v0.5.0 — informative background for the design decisions in this revision, not normative wire-protocol references:)*

[11] M. Tofte and J.-P. Talpin. "Region-Based Memory Management." *Information and Computation* 132(2), 1997.
[12] D. Grossman, G. Morrisett, T. Jim, M. Hicks, Y. Wang, J. Cheney. "Region-Based Memory Management in Cyclone." *PLDI* 2002.
[13] T. Jim, G. Morrisett, D. Grossman, M. Hicks, J. Cheney, Y. Wang. "Cyclone: A Safe Dialect of C." *USENIX ATC* 2002.
[14] R. Jung, J.-H. Jourdan, R. Krebbers, D. Dreyer. "RustBelt: Securing the Foundations of the Rust Programming Language." *POPL* 2018.
[15] D. Clarke, J. Potter, J. Noble. "Ownership Types for Flexible Alias Protection." *OOPSLA* 1998.

See [`docs/research-needed.md`](../docs/research-needed.md) for contributor work derived from these references.

---

_End of zbeam Technical Specification v0.5.0-draft_
