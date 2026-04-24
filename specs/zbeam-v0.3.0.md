# zbeam — Technical Specification

**Document Status**: Working Draft  
**Version**: 0.3.0-draft  
**Date**: 2026-04-22  
**Language**: Zig 0.16.0 (`std.Io` interface mandatory)  
**Compatibility Target**: OTP 25, 26, 27 (Erlang Distribution Protocol v5/v6)  
**Changes from v0.2.0**: Mailbox data race fixed, BufferHandle replaces BinaryView, io_uring buffer ring path added, demand-based receiver, transport/actor layer separation.

---

## Table of Contents

1. Abstract
2. Terminology & Conventions
3. Motivation & Prior Art
4. System Architecture
5. Module Specifications
    - 5.1 EPMD Client
    - 5.2 Handshake FSM
    - 5.3 ETF — External Term Format
    - 5.4 Distribution Protocol Layer
    - 5.5 Transport Layer ← **new, separated from actor layer**
    - 5.6 Actor Runtime
    - 5.7 Name Registry
    - 5.8 Effect Channel
6. NodeConfig & Public API
7. Node Lifecycle
8. Dist Connection Pool & Reconnect FSM
9. Wire Protocol Compliance
10. Type System & Safety Guarantees
11. Error Model
12. Memory Model
13. Concurrency Model
14. Security Model
15. Integration Contracts
16. Conformance Requirements
17. Non-Goals & Explicit Exclusions
18. Research Roadmap ← **new**
19. Versioning Policy
20. References

---

## 1. Abstract

zbeam is a native Zig library implementing the full Erlang Distribution Protocol (EDP v5/v6), enabling a Zig process to appear as a first-class BEAM node in an Erlang/OTP cluster.

v0.3.0 introduces two foundational changes over v0.2.0:

1. **Transport/Actor separation** — the TCP receive path and the actor mailbox are now cleanly separated layers. This enables io_uring buffer rings at the transport layer without touching actor semantics.
    
2. **Demand-based flow control** — actors declare capacity before the transport layer reads from TCP. TCP backpressure propagates naturally to the sender instead of being absorbed by an unbounded mailbox.
    

These two changes together address the core Zero-Copy Protocol Design problem and simultaneously prepare the architecture for future zero-copy internal message passing (see §18 Research Roadmap).

---

## 2. Terminology & Conventions

| Term             | Definition                                                    |
| ---------------- | ------------------------------------------------------------- |
| **BEAM**         | Bogdan/Björn's Erlang Abstract Machine                        |
| **EDP**          | Erlang Distribution Protocol                                  |
| **ETF**          | External Term Format — binary serialization of Erlang terms   |
| **EPMD**         | Erlang Port Mapper Daemon                                     |
| **Node**         | A named BEAM runtime instance (`foo@127.0.0.1`)               |
| **Actor**        | A zbeam fiber owning a mailbox, addressable by name or PID    |
| **Fiber**        | A stackful coroutine managed by zbeam's actor runtime         |
| **Transport**    | The TCP receive/send path — separated from actor logic        |
| **BufferHandle** | Zero-copy view into a transport-owned buffer arena            |
| **Demand**       | Actor-declared capacity — how many messages it can accept now |
| **BufferRing**   | io_uring pre-registered buffer pool for kernel-direct writes  |

RFC 2119 key words apply throughout.

---

## 3. Motivation & Prior Art

### 3.1 Problem Statement (updated)

v0.2.0 identified the Zero-Copy Protocol Design problem but did not solve it. The root cause has two parts:

**Part A — Copy at kernel boundary**: data arrives from NIC into kernel buffer, then copied again into userspace recv buffer before ETF decode even starts.

**Part B — Absorbed backpressure**: the mailbox sits between the TCP socket and the actor. When the actor is slow, the mailbox grows silently. TCP never sees receiver-side slowness, so the sender is never naturally throttled.

v0.3.0 targets both:

|Problem|v0.2.0|v0.3.0|
|---|---|---|
|Kernel→userspace copy|`recv()` into temp buffer|io_uring buffer rings (research needed)|
|Cross-process copy|ETF copy at every actor boundary|`BufferHandle` zero-copy within same node|
|TCP backpressure absorbed|Mailbox grows unbounded|Demand-based receiver — TCP reads gated on actor demand|
|Mailbox data race|`LinearFifo` without synchronization|Mutex-guarded queue + `Io.Event`|

### 3.2 Prior Art

|Project|Language|EDP|ETF|Zero-Copy Transport|Demand Flow Control|
|---|---|---|---|---|---|
|Ergo|Go|Full|Full|No|No|
|erl_dist|Rust|Partial|Partial|No|No|
|**zbeam v0.3.0**|Zig|Full|Full|Partial (research needed)|Yes|

---

## 4. System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         BEAM Cluster                            │
│   elixir@host          erlang@host          gleam@host          │
└──────────────────────────────┬──────────────────────────────────┘
                               │  TCP (EDP v5/v6)
┌──────────────────────────────▼──────────────────────────────────┐
│                     zbeam@host (Zig OS Process)                 │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                   TRANSPORT LAYER  (§5.5)               │    │
│  │                                                         │    │
│  │  BufferRing (io_uring)  ←──── kernel writes direct      │    │
│  │       │                                                 │    │
│  │  RecvLoop  ←── gated by actor Demand signal             │    │
│  │       │                                                 │    │
│  │  FragmentReassembler                                    │    │
│  │       │                                                 │    │
│  │  ETF Decode ──► BufferHandle (zero-copy reference)      │    │
│  └──────────────────────────┬──────────────────────────────┘    │
│                             │  BufferHandle (no copy)           │
│  ┌──────────────────────────▼──────────────────────────────┐    │
│  │                   ACTOR LAYER  (§5.6)                   │    │
│  │                                                         │    │
│  │  Mailbox (mutex-guarded) ←── deliver(BufferHandle)      │    │
│  │       │                                                 │    │
│  │  Actor Fiber  ──► requestMore(n)  ──► Demand signal     │    │
│  │       │                             back to Transport   │    │
│  │  Link/Monitor Tables                                    │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

### 4.1 Design Invariants

1. **No shared mutable state between actors** — each fiber owns its stack and heap region.
2. **BufferHandle is the unit of zero-copy transfer** within a single zbeam node.
3. **ETF is only serialized at the wire boundary** — actor-to-actor within the same node uses `BufferHandle` ownership transfer, not ETF re-encode. _(internal ETF-free path is a future research goal — see §18)_
4. **Transport layer does not read TCP unless actor has declared demand** — backpressure propagates naturally.
5. **Every panic is caught before crossing node boundary.**
6. **Mailbox access is always mutex-guarded** — no assumption about single-threaded backend.

---

## 5. Module Specifications

### 5.1 EPMD Client

_(Unchanged from v0.2.0 — spec is correct)_

```zig
pub const EpmdClient = struct {
    pub const RegistrationResult = struct { creation: u16 };

    pub fn register(
        io: std.Io,
        allocator: std.mem.Allocator,
        node_name: []const u8,
        listen_port: u16,
    ) !RegistrationResult;

    pub fn lookupNode(
        io: std.Io,
        allocator: std.mem.Allocator,
        node_name: []const u8,
    ) !NodeInfo;
};
```

---

### 5.2 Handshake FSM

_(Unchanged from v0.2.0)_

State machine: `IDLE → SEND_NAME → RECV_STATUS → RECV_CHALLENGE → SEND_CHALLENGE_REPLY → RECV_CHALLENGE_ACK → CONNECTED`

Both initiating and accepting roles MUST be implemented.

---

### 5.3 ETF — External Term Format

#### 5.3.1 BufferHandle — Replaces BinaryView

`BinaryView` from v0.2.0 is replaced by `BufferHandle`. The critical difference: `BinaryView` tied lifetime to the recv buffer. `BufferHandle` ties lifetime to a named arena that can be extended, transferred, or promoted — enabling future zero-copy actor-to-actor passing (§18.1).

```zig
pub const BufferHandle = struct {
    bytes:    []const u8,
    arena_id: u32,        // which transport arena owns this memory
    // arena_id == 0 → stack/temp, must call toOwned() before any async boundary
    // arena_id >  0 → transport arena, valid until arena is recycled

    // MUST call if handle outlives current message handler,
    // or if it will cross an actor boundary (until §18.1 is implemented).
    pub fn toOwned(self: BufferHandle, allocator: std.mem.Allocator) ![]u8 {
        return allocator.dupe(u8, self.bytes);
    }

    // Promote to actor-owned — transfers arena ownership, zero-copy.
    // (research needed — see §18.1 for full design)
    pub fn promote(self: BufferHandle, runtime: *ActorRuntime) !OwnedHandle {
        _ = self;
        _ = runtime;
        @compileError("promote() not yet implemented — see §18.1");
    }
};
```

Lifetime rules:

- `BufferHandle` is valid for the duration of the current message handler call.
- If the actor calls `receive()` again, the previous handle's backing memory MAY be overwritten by the next recv.
- Call `toOwned()` to escape the handler scope safely.
- `promote()` is the hook for future zero-copy actor transfer (§18.1).

#### 5.3.2 Comptime Typed Decode — Mode 1

_(Unchanged from v0.2.0, except binary decode returns `BufferHandle` not `[]const u8`)_

```zig
pub fn decode(comptime T: type, reader: anytype, arena_id: u32) !T;
```

#### 5.3.3 Dynamic Decode — Mode 2

`Term.binary` now carries `BufferHandle` instead of raw `[]const u8`:

```zig
pub const Term = union(enum) {
    integer: i64,
    float:   f64,
    atom:    Atom,
    binary:  BufferHandle,   // ← was BinaryView
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

#### 5.3.4 Atom Interning & Cache

_(Unchanged from v0.2.0)_

#### 5.3.5 PID & Ref Generation

_(Unchanged from v0.2.0)_

---

### 5.4 Distribution Protocol Layer

_(Message framing, control messages, heartbeat, fragment reassembly — unchanged from v0.2.0)_

Fragment reassembly output is now passed as `BufferHandle` into the transport layer (§5.5) instead of being decoded inline. This separates reassembly from ETF decode.

---

### 5.5 Transport Layer ← NEW

This section replaces the inline recv logic that was previously embedded in §5.4. The transport layer owns:

- The recv buffer arena (io_uring buffer rings when available)
- Fragment reassembly
- ETF decode
- Demand gating — reads from TCP only when actor has capacity

#### 5.5.1 Buffer Arena

Each connection owns a `TransportArena` — a slab of pre-allocated buffers that the kernel writes into directly when io_uring is available.

```zig
pub const TransportArena = struct {
    // Slab of fixed-size buffers — registered with io_uring kernel side.
    // (research needed for io_uring buffer ring registration — see §18.2)
    buffers:    []align(4096) u8,
    buffer_size: usize,
    count:       usize,
    next_id:     std.atomic.Value(u32),

    pub fn init(allocator: std.mem.Allocator, count: usize, buffer_size: usize) !TransportArena {
        const buffers = try allocator.alignedAlloc(u8, 4096, count * buffer_size);
        return .{
            .buffers     = buffers,
            .buffer_size = buffer_size,
            .count       = count,
            .next_id     = std.atomic.Value(u32).init(0),
        };
    }

    // Returns a buffer slot. Wraps around (ring behavior).
    pub fn acquireSlot(self: *TransportArena) BufferSlot {
        const id = self.next_id.fetchAdd(1, .monotonic) % @intCast(self.count);
        const start = id * self.buffer_size;
        return .{
            .id    = id,
            .bytes = self.buffers[start .. start + self.buffer_size],
        };
    }

    pub const BufferSlot = struct {
        id:    u32,
        bytes: []u8,
    };
};
```

`arena_id` in `BufferHandle` maps directly to `TransportArena.BufferSlot.id`. This is how the actor layer knows which buffer it is referencing.

#### 5.5.2 io_uring Buffer Ring Registration (research needed)

When the runtime detects Linux kernel >= 5.19 and `std.Io.Evented` backend, the transport layer SHOULD register `TransportArena.buffers` with the kernel via `IORING_OP_PROVIDE_BUFFERS`. This eliminates the kernel→userspace copy:

```
Standard path:
  kernel buffer → memcpy → TransportArena.buffers → ETF decode

io_uring buffer ring path:
  kernel writes directly into TransportArena.buffers → ETF decode
  (no copy)
```

The API surface for this is currently not exposed by `std.Io` in Zig 0.16. **This requires either:**

- A custom `std.Io` backend that wraps `io_uring` directly via `std.os.linux`
- Or waiting for `std.Io.Evented` to expose buffer ring registration

Design constraint: the rest of zbeam MUST NOT know or care whether the buffer ring path is active. `TransportArena` is the abstraction boundary. `BufferHandle.arena_id` is valid in both paths.

**Fallback**: when buffer rings are unavailable, `TransportArena` behaves as a standard slab allocator with `recv()` syscall. Zero-copy from actor layer inward is preserved; only the kernel→userspace copy remains.

#### 5.5.3 Demand-Based Receiver

The transport layer's recv loop MUST NOT read from TCP unless the actor has declared demand. This is the mechanism by which TCP backpressure propagates naturally to the sender.

```zig
pub const DemandSignal = struct {
    // Actor writes here to declare capacity.
    // Transport reads here before each TCP read.
    available: std.atomic.Value(u32),

    pub fn init(initial: u32) DemandSignal {
        return .{ .available = std.atomic.Value(u32).init(initial) };
    }

    // Called by actor after consuming a message — declares it can accept one more.
    pub fn grantOne(self: *DemandSignal) void {
        _ = self.available.fetchAdd(1, .release);
    }

    // Called by transport before reading from TCP.
    // Returns false if no demand — transport MUST NOT read TCP.
    pub fn tryConsume(self: *DemandSignal) bool {
        var current = self.available.load(.acquire);
        while (current > 0) {
            if (self.available.cmpxchgWeak(
                current, current - 1, .acq_rel, .acquire
            )) |_| {
                current = self.available.load(.acquire);
                continue;
            }
            return true;
        }
        return false;
    }
};

pub fn recvLoop(io: std.Io, conn: *PeerConnection, mailbox: *Mailbox) !void {
    while (conn.state == .connected) {
        // Gate: do not read TCP until actor has capacity.
        // When demand == 0, this loop yields cooperatively.
        // TCP kernel buffer fills up → TCP window shrinks → sender slows down.
        // Backpressure propagates naturally.
        while (!mailbox.demand.tryConsume()) {
            try io.yield();
        }

        const slot  = conn.arena.acquireSlot();
        const frame = try readFrameIntoSlot(io, conn, slot);
        const term  = try etfDecode(frame, slot.id); // arena_id = slot.id

        try mailbox.deliver(term);
    }
}
```

**Why this propagates TCP backpressure:** When `demand == 0`, `recvLoop` calls `io.yield()` instead of reading from TCP. The kernel's TCP receive buffer for this connection stops being drained. Once it fills up, the kernel shrinks the TCP receive window to zero, which is transmitted to the sender in ACK packets. The sender's TCP stack is then blocked from sending more data. This is standard TCP flow control — zbeam simply stops interfering with it.

**Contrast with v0.2.0**: the old `recvLoop` read from TCP unconditionally, filling the mailbox. The mailbox absorbed the backpressure signal entirely.

#### 5.5.4 Transport Layer Interface

```zig
pub const TransportLayer = struct {
    arena:      TransportArena,
    reassembler: FragmentReassembler,

    pub fn init(allocator: std.mem.Allocator, config: NodeConfig) !TransportLayer;

    // Start recv loop for a connection. Runs as concurrent task.
    pub fn runRecv(
        self: *TransportLayer,
        io:      std.Io,
        conn:    *PeerConnection,
        mailbox: *Mailbox,
    ) !void;

    // Encode and send a term to a peer. ETF encode happens here — only at wire boundary.
    pub fn send(
        self: *TransportLayer,
        io:   std.Io,
        conn: *PeerConnection,
        term: anytype,
    ) !void;
};
```

---

### 5.6 Actor Runtime

#### 5.6.1 Actor Identity

_(Unchanged from v0.2.0)_

#### 5.6.2 I/O Model

_(Unchanged from v0.2.0 — `std.Io` as backend)_

#### 5.6.3 Concurrent Actor Spawn via Io.Group

_(Unchanged from v0.2.0)_

#### 5.6.4 Actor Body & Receive

After consuming a message, the actor MUST call `requestMore` to grant demand back to the transport layer:

```zig
fn myActor(io: std.Io, ctx: ActorContext) !void {
    // Grant initial demand — actor is ready to receive N messages.
    ctx.mailbox.demand.grantOne();

    while (true) {
        const msg = try ctx.mailbox.receive(io);

        switch (msg) {
            .compute => |data| {
                const result = heavyCompute(data.bytes);
                try ctx.send(io, msg.from, .{ .result, result });
            },
            .stop => break,
        }

        // Grant demand for next message AFTER processing current one.
        // This is the backpressure signal back to transport.
        ctx.mailbox.demand.grantOne();
    }
}
```

#### 5.6.5 Mailbox — Fixed Data Race

v0.2.0 had an undefined behavior data race: `LinearFifo` was accessed from both the dist receiver task and the actor task without synchronization. Under `std.Io.Threaded`, these run on different OS threads simultaneously.

v0.3.0 fixes this with a mutex guarding all queue access:

```zig
pub const Mailbox = struct {
    queue:  std.fifo.LinearFifo(Term, .Dynamic),
    event:  std.Io.Event,
    mutex:  std.Thread.Mutex,           // ← added
    demand: DemandSignal,               // ← added

    pub fn init(allocator: std.mem.Allocator, initial_demand: u32) Mailbox {
        return .{
            .queue  = std.fifo.LinearFifo(Term, .Dynamic).init(allocator),
            .event  = .{},
            .mutex  = .{},
            .demand = DemandSignal.init(initial_demand),
        };
    }

    // Called from transport layer task — potentially different OS thread.
    pub fn deliver(self: *Mailbox, msg: Term) !void {
        self.mutex.lock();
        try self.queue.writeItem(msg);
        self.mutex.unlock();
        // set() AFTER unlock — event signals availability, not guards data.
        // If set() were inside the lock, actor wakeup would contend with deliver().
        self.event.set();
    }

    // Called from actor task.
    pub fn receive(self: *Mailbox, io: std.Io) !Term {
        while (true) {
            self.mutex.lock();
            if (self.queue.count > 0) {
                const msg = self.queue.readItem().?;
                self.mutex.unlock();
                return msg;
            }
            self.mutex.unlock();
            // wait() OUTSIDE lock — if inside, deliver() would deadlock
            // trying to acquire the mutex while actor sleeps holding it.
            try self.event.wait(io);
            self.event.reset();
        }
    }
};
```

**Why `event.set()` must be after `mutex.unlock()`:** `set()` wakes the actor. If the actor wakes while deliver still holds the mutex, the actor immediately blocks on `mutex.lock()` — unnecessary contention on every message delivery. Unlocking first, then signaling, means the actor wakes into an uncontended lock.

**Why `event.wait()` must be outside the lock:** If the actor held the mutex while waiting, `deliver()` would deadlock trying to acquire the same mutex to write the message.

#### 5.6.6 Reduction Accounting

_(Unchanged from v0.2.0)_

#### 5.6.7 Link & Monitor Tables

_(Unchanged from v0.2.0)_

---

### 5.7 Name Registry

_(Unchanged from v0.2.0)_

---

### 5.8 Effect Channel

_(Unchanged from v0.2.0)_

---

## 6. NodeConfig & Public API

```zig
pub const NodeConfig = struct {
    // --- Identity ---
    node_name:  []const u8,
    cookie:     []const u8,

    // --- Network ---
    listen_port: u16 = 0,
    epmd_host:   []const u8 = "127.0.0.1",
    epmd_port:   u16 = 4369,

    // --- Transport Buffer Ring ---
    // Number of pre-allocated transport buffers per connection.
    // Each buffer is transport_buffer_size bytes.
    // Higher = more concurrent in-flight messages without copy.
    // (research needed — optimal value depends on io_uring availability)
    transport_buffer_count: u32 = 64,
    transport_buffer_size:  u32 = 65_536, // 64KB — covers most dist frames

    // --- Demand / Flow Control ---
    // Initial demand granted to each actor on spawn.
    // Controls how many messages can be in-flight per actor before backpressure.
    // 0 = actor must manually call grantOne() before first receive().
    // Default: 1 — conservative, actor controls its own pace.
    initial_actor_demand: u32 = 1,

    // --- Limits ---
    max_message_size: u32 = 134_217_728, // 128 MiB
    max_actors:       u32 = 65_536,
    mailbox_max_depth: u32 = 0,          // 0 = unbounded (demand provides real control now)

    // --- Scheduler ---
    reduction_budget: u32 = 2_000,

    // --- Reconnect ---
    reconnect_backoff_min_ms: u32 = 500,
    reconnect_backoff_max_ms: u32 = 30_000,
    reconnect_max_attempts:   u32 = 0,
};
```

**Note on `mailbox_max_depth`:** In v0.2.0 this was the only backpressure mechanism and was documented as "unbounded — caller is responsible." In v0.3.0, demand-based flow control provides real backpressure at the TCP level. `mailbox_max_depth` becomes a last-resort safety net, not the primary control mechanism.

---

## 7. Node Lifecycle

### 7.1 Startup Sequence

```
zbeam.start(io, allocator, config)
  │
  ├─ 1. Validate NodeConfig
  ├─ 2. Bind TCP listener
  ├─ 3. Register with EPMD
  ├─ 4. Initialize subsystems
  │       AtomTable, Registry, LinkTable, MonitorTable, PidGenerator, RefGenerator
  │
  ├─ 5. Initialize TransportLayer          ← NEW
  │       TransportArena.init(buffer_count, buffer_size)
  │       Attempt io_uring buffer ring registration if kernel >= 5.19  (research needed)
  │       Fall back to standard recv if unavailable — transparent to rest of system
  │
  ├─ 6. Initialize ActorRuntime (Io.Group)
  ├─ 7. Start listener task
  └─ 8. Return Node handle
```

### 7.2 Shutdown Sequence

_(Unchanged from v0.2.0 — order is correct)_

### 7.3 Actor Panic Containment

_(Unchanged from v0.2.0)_

---

## 8. Dist Connection Pool & Reconnect FSM

### 8.1 Connection States

_(Unchanged from v0.2.0)_

### 8.2 Reconnect — Demand Reset on Reconnect

When a connection reconnects, the `DemandSignal` for all affected mailboxes MUST be reset to `initial_actor_demand`. During the disconnected window, TCP was not being read. On reconnect, actors need to re-grant demand explicitly before the transport layer starts reading again.

```zig
pub fn onReconnect(self: *PeerConnection, mailboxes: []*Mailbox, config: NodeConfig) void {
    self.atom_cache.reset();
    for (mailboxes) |mailbox| {
        // Reset demand — actor will re-grant after it's ready.
        mailbox.demand = DemandSignal.init(config.initial_actor_demand);
    }
    self.state = .connected;
}
```

### 8.3 Connection Pool

_(Unchanged from v0.2.0, `TransportLayer` is passed in and reused per connection)_

### 8.4 Tick / Heartbeat

_(Unchanged from v0.2.0)_

---

## 9. Wire Protocol Compliance

_(Unchanged from v0.2.0)_

---

## 10. Type System & Safety Guarantees

### 10.1 Phantom Types for PID Safety

_(Unchanged from v0.2.0)_

### 10.2 Session Types for Protocol Channels

_(Unchanged from v0.2.0)_

### 10.3 BufferHandle Lifetime — Compile-Time Enforcement (research needed)

Currently `BufferHandle` lifetime is documented but not enforced at compile time. Full compile-time enforcement requires comptime lifetime tracking — see §18.1.

The current contract:

- `BufferHandle` passed to actor handler is valid for that handler call only.
- Crossing async boundary without `toOwned()` is a logic error.
- `promote()` stub is in place for future zero-copy cross-actor transfer.

---

## 11. Error Model

### 11.1 Error Categories

```zig
pub const EpmdError = error{
    ConnectionRefused, EpmdUnavailable, RegistrationFailed, NodeNotFound, InvalidConfig,
};

pub const HandshakeError = error{
    InvalidCookie, ProtocolVersionMismatch, UnexpectedMessage, ConnectionReset,
};

pub const DistError = error{
    InvalidFrame, UnknownControlTag, EtfDecodeError, ActorNotFound,
    MailboxFull, TickTimeout,
};

pub const EtfError = error{
    UnknownTag, TruncatedData, UnsupportedType, AtomTooLong,
    TypeMismatch, ArityMismatch, InvalidVersion,
};

pub const TransportError = error{   // ← NEW
    BufferRingUnavailable,          // io_uring not supported — fallback active
    ArenaExhausted,                 // all buffer slots in use — increase transport_buffer_count
    DemandDeadlock,                 // demand never granted — actor not calling grantOne()
};
```

### 11.2 Error Propagation to BEAM

_(Unchanged from v0.2.0)_

---

## 12. Memory Model

### 12.1 Allocator Architecture

|Tier|Allocator|Scope|Purpose|
|---|---|---|---|
|Global|`GeneralPurposeAllocator`|Process lifetime|Node tables, connection state|
|Transport|`TransportArena` (slab)|Connection lifetime|Recv buffers — io_uring registered|
|Per-message|Fixed-buffer from transport arena|Message handler|ETF decode — `BufferHandle` points here|
|Actor-owned|Arena per actor|Actor lifetime|`toOwned()` copies live here|

**Key change from v0.2.0**: the "Per-connection arena" and "Per-message fixed-buffer" tiers are now unified under `TransportArena`. `BufferHandle.arena_id` identifies which slot in the slab a given handle references.

### 12.2 Ownership Rules

1. Messages in the transport arena are owned by `TransportLayer` until `deliver()`.
2. After `deliver()`, the message (`Term` with embedded `BufferHandle`) is owned by the mailbox queue.
3. After `receive()`, the message is owned by the actor's stack frame for the duration of the handler call.
4. `BufferHandle` backing memory is valid until `recvLoop` overwrites that arena slot in the next round-trip. Call `toOwned()` to escape.
5. Data passed to `Effects.Send` destined for a **remote BEAM node** is ETF-encoded into an outgoing buffer — actor retains the original.
6. Data passed to `Effects.Send` destined for a **local zbeam actor** uses `BufferHandle` transfer — no ETF re-encode. _(full zero-copy transfer is §18.1)_

---

## 13. Concurrency Model

### 13.1 Foundation: std.Io

_(Unchanged from v0.2.0)_

### 13.2 Structural Concurrency via Io.Group

```
Main (io.Group: node_group)
  ├── EPMD registration task
  ├── Listener task (io.Group: connection_group per peer)
  │     ├── handlePeerConnection(peer_A)
  │     │     ├── TransportLayer.runRecv  ← gated by demand
  │     │     └── TransportLayer.send
  │     └── handlePeerConnection(peer_B)
  └── Actor group (io.Group: actor_group)
        ├── actor_fiber(pid_1)  ← controls own demand via mailbox.demand.grantOne()
        ├── actor_fiber(pid_2)
        └── actor_fiber(pid_N)
```

### 13.3 Demand Signal — Concurrency Contract

`DemandSignal.available` is `std.atomic.Value(u32)`.

- `grantOne()` uses `.release` memory order — ensures all actor writes before grant are visible to transport thread.
- `tryConsume()` uses `.acq_rel` — ensures transport sees actor's writes, and actor will see transport's subsequent writes.

This is the only synchronization point between actor task and transport task that is **not** mediated by the mailbox mutex. It is intentionally separate — the mutex guards data integrity, the demand signal guards read permission.

### 13.4 Task Lifecycle Rules

_(Unchanged from v0.2.0)_

### 13.5 Synchronization via std.Io.Event

_(Unchanged from v0.2.0)_

---

## 14. Security Model

_(Unchanged from v0.2.0)_

---

## 15. Integration Contracts

_(Unchanged from v0.2.0 — wire semantics are identical)_

---

## 16. Conformance Requirements

### 16.1 Test Suite Categories

_(All categories from v0.2.0 remain, with additions)_

|Category|Tests|Tooling|
|---|---|---|
|All v0.2.0 categories|...|...|
|**Backpressure**|Slow actor does not OOM; sender is throttled within 10s|Custom load harness|
|**Demand flow**|Actor receives exactly N messages after granting N demand|Elixir ExUnit|
|**Buffer ring fallback**|Correct behavior when io_uring unavailable|Mock `std.Io`|
|**Mailbox thread safety**|No data race under `std.Io.Threaded` with 16 threads|TSAN / Zig sanitizers|

### 16.2 Thread Safety Test (new, critical)

```zig
test "mailbox: no data race under concurrent deliver and receive" {
    // Run with: zig test --sanitize thread
    var mailbox = Mailbox.init(allocator, 0);
    var group: std.Io.Group = .init;
    defer group.cancel(io);

    // 8 concurrent deliver tasks
    for (0..8) |_| {
        try group.concurrent(io, deliverSpam, .{ io, &mailbox });
    }

    // 1 receive task
    try group.concurrent(io, receiveAll, .{ io, &mailbox });
}
```

---

## 17. Non-Goals & Explicit Exclusions

_(All v0.2.0 non-goals remain, with one addition)_

- **Full zero-copy actor-to-actor message passing** — `BufferHandle.promote()` is stubbed. The architecture is designed to support it (§18.1) but it is not implemented in v0.3.0.

---

## 18. Research Roadmap ← NEW

This section documents the research directions that v0.3.0's architecture is explicitly designed to enable. None of these are implemented in v0.3.0. They are listed here because the design decisions in §5.5.1 (`TransportArena`), §5.3.1 (`BufferHandle.arena_id`), and §5.3.1 (`BufferHandle.promote()`) would need to be redesigned if this roadmap is abandoned.

### 18.1 Zero-Copy Actor-to-Actor Message Passing (research needed)

**Problem**: when a zbeam actor sends a `BufferHandle` to another local zbeam actor, v0.3.0 currently requires `toOwned()` — a copy. The ETF-free internal protocol vision is: ownership of the `TransportArena` slot is transferred to the receiver, zero copy.

**Research question**: can Zig's `comptime` enforce that after `promote()`, the sender cannot access the buffer? This simulates linear types without requiring them at the language level.

**Prerequisite already in place**: `BufferHandle.arena_id` — the receiver can identify and reference the exact buffer slot without knowing the sender's stack. `promote()` stub exists in §5.3.1.

**What needs to be designed**:

- Arena slot reference counting or ownership flag
- `comptime` enforcement that promoted handles are not used after transfer
- Whether arena_id namespace needs to be global across all connections or per-connection

### 18.2 io_uring Buffer Ring Full Integration (research needed)

**Problem**: `std.Io` in Zig 0.16 does not expose `IORING_OP_PROVIDE_BUFFERS`. `TransportArena` is aligned and pre-allocated correctly — the buffers are ready to be registered. The missing piece is the registration call.

**Research question**: is it acceptable to drop below `std.Io` to `std.os.linux` directly for buffer ring registration, while keeping all other I/O through `std.Io`? What are the interaction effects with `std.Io.Group` task cancellation?

**Prerequisite already in place**: `TransportArena` with 4096-aligned allocation, `arena_id` tracking, `BufferHandle` abstraction boundary in §5.5.1.

### 18.3 Demand Composition with GenStage (research needed)

**Problem**: demand-based receiver in §5.5.3 is per-actor. When multiple actors consume from one connection (fan-out), demand signals need to be composed.

**Research question**: can the `DemandSignal` be generalized to a multi-consumer demand combinator that maps naturally to GenStage's pull model on the Elixir side? This would make zbeam a native participant in Broadway pipelines.

### 18.4 Session Types for BufferHandle Lifetime (research needed)

**Problem**: `BufferHandle` lifetime is enforced by documentation, not the type system.

**Research question**: can Zig's `comptime` phase-type pattern (already used in `HandshakeState` in §10.2) be applied to `BufferHandle` to make out-of-scope access a compile error? See reference [9] Multiparty Session Types for theoretical grounding.

---

## 19. Versioning Policy

_(Unchanged from v0.2.0)_

**Minimum Zig version: 0.16.0**

---

## 20. References

|#|Title|URL|
|---|---|---|
|[1]|Erlang Distribution Protocol|https://www.erlang.org/doc/apps/erts/erl_dist_protocol.html|
|[2]|External Term Format|https://www.erlang.org/doc/apps/erts/erl_ext_dist.html|
|[3]|EPMD Man Page (OTP 26)|https://www.erlang.org/docs/26/man/epmd|
|[4]|RFC 2119|https://www.rfc-editor.org/rfc/rfc2119|
|[5]|Zig 0.16.0 Language Reference|https://ziglang.org/documentation/0.16.0/|
|[6]|Zig 0.16.0 Release Notes (std.Io)|https://ziglang.org/download/0.16.0/release-notes.html|
|[7]|io_uring buffer rings|https://kernel.dk/io_uring.pdf|
|[8]|IORING_OP_PROVIDE_BUFFERS — kernel 5.19|https://git.kernel.org/torvalds/c/dbc31bc|
|[9]|Multiparty Session Types — Fowler et al.|https://arxiv.org/pdf/1608.03321|
|[10]|Safe Actor Programming with MPST (2026)|https://arxiv.org/abs/2602.24054|
|[11]|Ergo Framework (Go reference impl)|https://github.com/ergo-services/proto|
|[12]|GenStage — demand-driven data exchange|https://hexdocs.pm/gen_stage|
|[13]|SemVer 2.0.0|https://semver.org|

---

_End of zbeam Technical Specification v0.3.0-draft_