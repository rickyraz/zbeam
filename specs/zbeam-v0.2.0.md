# zbeam — Technical Specification

**Document Status**: Working Draft  
**Version**: 0.2.0-draft  
**Date**: 2026-04-18  
**Language**: Zig 0.16.0 (minimum required — `std.Io` interface mandatory)  
**Compatibility Target**: OTP 25, 26, 27 (Erlang Distribution Protocol v5/v6)

---

## Table of Contents

1. Abstract
2. Terminology & Conventions
3. Motivation & Prior Art
4. System Architecture
5. Module Specifications
   - 5.1 EPMD Client
   - 5.2 Handshake FSM
   - 5.3 ETF — External Term Format (Encoder + Decoder)
   - 5.4 Distribution Protocol Layer
   - 5.5 Actor Runtime
   - 5.6 Name Registry
   - 5.7 Effect Channel
6. NodeConfig & Public API
7. Node Lifecycle (Start / Shutdown)
8. Dist Connection Pool & Reconnect FSM
9. Wire Protocol Compliance
10. Type System & Safety Guarantees
11. Error Model
12. Memory Model
13. Concurrency Model
14. Security Model
15. Integration Contracts (Elixir / Erlang / Gleam)
16. Conformance Requirements
17. Non-Goals & Explicit Exclusions
18. Versioning Policy
19. References

---

## 1. Abstract

zbeam is a native Zig library that implements the full Erlang Distribution Protocol (EDP v5/v6), enabling a Zig process to appear as a first-class BEAM node in an Erlang/OTP cluster. A zbeam node can be addressed by name (`zbeam@host`), exchange messages using External Term Format (ETF), participate in OTP supervision via `link`/`monitor`, and expose named actors visible as registered processes from any BEAM language (Erlang, Elixir, Gleam).

zbeam does **not** modify OTP, does **not** embed inside a BEAM VM, and does **not** use NIF or Port Driver APIs. It is a standalone network peer that speaks the distribution protocol natively.

---

## 2. Terminology & Conventions

| Term             | Definition                                                                         |
| ---------------- | ---------------------------------------------------------------------------------- |
| **BEAM**         | Bogdan/Björn's Erlang Abstract Machine — the runtime for Erlang, Elixir, and Gleam |
| **EDP**          | Erlang Distribution Protocol — wire protocol for inter-node communication          |
| **ETF**          | External Term Format — binary serialization of Erlang terms                        |
| **EPMD**         | Erlang Port Mapper Daemon — node name registry                                     |
| **Node**         | A named BEAM runtime instance (e.g., `foo@127.0.0.1`)                              |
| **Actor**        | A zbeam fiber that owns a mailbox and can be addressed by name or opaque PID       |
| **Fiber**        | A stackful coroutine managed by zbeam's actor runtime                              |
| **PCB**          | Process Control Block — BEAM's internal per-process structure                      |
| **Session Type** | Compile-time protocol type enforced across communication boundaries                |
| **Capability**   | An unforgeable token granting the right to perform an operation                    |

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHOULD", "RECOMMENDED", and "MAY" in this document follow RFC 2119 semantics.

---

## 3. Motivation & Prior Art

### 3.1 Problem Statement

Existing approaches to integrate native code with BEAM fall into three categories:

| Approach | Identity | Isolation | Fault boundary |
|---|---|---|---|
| NIF (Rustler, Zigler) | None — called in-process | None | Crash = BEAM crash |
| Port Driver | Port identifier | Partial | Crash kills port |
| Port (stdin/stdout) | Port identifier | Full process | Crash = port close |
| **zbeam** | Full BEAM node | Full OS process | Crash = node down |

zbeam is the only approach where a Zig runtime has a **first-class node identity** and **full OTP fault semantics** without modifying OTP internals.

### 3.2 Prior Art

| Project | Language | EDP | ETF | Actor | Status |
|---|---|---|---|---|---|
| Ergo | Go | Full | Full | Yes | Active |
| erlang_node (Python) | Python | Partial | Partial | No | Unmaintained |
| erl_dist (Rust) | Rust | Partial | Partial | No | Inactive |
| **zbeam** | Zig | Full | Full | Yes | This spec |

zbeam differs from all prior art in: zero runtime allocator dependency, comptime ETF type generation, and reduction-aware cooperative scheduling.

---

## 4. System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         BEAM Cluster                            │
│   elixir@host          erlang@host          gleam@host          │
└──────────────────────────────┬──────────────────────────────────┘
                               │  TCP (EDP v5/v6)
                               │  Cookie-authenticated
┌──────────────────────────────▼──────────────────────────────────┐
│                     zbeam@host (Zig OS Process)                  │
│                                                                  │
│  ┌────────────┐  ┌──────────────┐  ┌─────────────────────────┐  │
│  │ EPMD Client│  │ Handshake FSM│  │   Dist Connection Pool  │  │
│  │            │  │              │  │   (one TCP per peer)    │  │
│  │ register   │  │ send_name    │  │                         │  │
│  │ lookup     │  │ recv_status  │  │   fragment assembly     │  │
│  │ alive2_req │  │ recv_chal..  │  │   tick heartbeat        │  │
│  └────────────┘  │ send_chal..  │  │   flow control          │  │
│                  │ recv_ack     │  └────────────┬────────────┘  │
│                  └──────────────┘               │               │
│                                                 │               │
│  ┌──────────────────────────────────────────────▼─────────────┐ │
│  │                    ETF Codec (comptime)                     │ │
│  │  encode: Zig type → binary  |  decode: binary → Zig type   │ │
│  │  zero-copy for binary/bitstring              phantom types  │ │
│  └──────────────────────────────────────────────┬─────────────┘ │
│                                                 │               │
│  ┌──────────────────────────────────────────────▼─────────────┐ │
│  │                  Actor Runtime                              │ │
│  │  Fiber pool  |  Mailbox  |  Reduction counter              │ │
│  │  Named registry  |  Link table  |  Monitor table           │ │
│  └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### 4.1 Design Invariants

1. **No shared mutable state between actors** — each fiber owns its stack and heap region.
2. **All cross-actor data transfer via ETF terms** — no raw pointer passing.
3. **Every external operation is an effect** — I/O, send, spawn declared as typed capabilities.
4. **Panic is always caught before crossing the node boundary** — no panic propagates to a connected BEAM node.

---

## 5. Module Specifications

### 5.1 EPMD Client

**Reference**: [EPMD Protocol](https://www.erlang.org/docs/26/man/epmd) — Section 3 "EPMD Client Operations"

EPMD runs on port 4369 by default (configurable via `ERL_EPMD_PORT`). zbeam MUST implement the following EPMD request types:

#### 5.1.1 ALIVE2_REQ (Register Node)

```
1 byte : 'x' (0x78) — ALIVE2_REQ tag
2 bytes: port (big-endian) — port zbeam listens on
1 byte : node_type = 77 (0x4D) — 'M' = normal node
1 byte : protocol = 0 (TCP/IPv4)
2 bytes: highest_version = 6
2 bytes: lowest_version = 5
2 bytes: nlen (node name length)
N bytes: node name (UTF-8, no '@host' — only the name part)
2 bytes: elen = 0 (no extra data)
```

Response:
```
1 byte : 'y' (0x79) — ALIVE2_RESP
1 byte : result (0 = success)
2 bytes: creation (unique per registration, used in PID construction)
```

#### 5.1.2 PORT2_REQ (Lookup Node)

```
1 byte : 'z' (0x7A) — PORT2_REQ
N bytes: node name
```

#### 5.1.3 NAMES_REQ (List Nodes)

```
1 byte : 'n' (0x6E) — NAMES_REQ
```

#### 5.1.4 Zig Interface

```zig
pub const EpmdClient = struct {
    pub const RegistrationResult = struct {
        creation: u16,
    };

    pub fn register(
        allocator: std.mem.Allocator,
        node_name: []const u8,
        listen_port: u16,
    ) !RegistrationResult;

    pub fn lookupNode(
        allocator: std.mem.Allocator,
        node_name: []const u8,
    ) !NodeInfo;

    pub fn listNodes(
        allocator: std.mem.Allocator,
    ) ![]NodeInfo;
};
```

---

### 5.2 Handshake FSM

**Reference**: [Distribution Handshake](https://www.erlang.org/doc/apps/erts/erl_dist_protocol.html#distribution-handshake)

The handshake is a 5-step finite state machine. zbeam MUST implement both the **initiating** (connect) and **accepting** (listen) roles.

#### 5.2.1 State Machine (Initiating Role)

```
IDLE
  │  tcp_connect(host, port)
  ▼
SEND_NAME
  │  send: name_msg {flags, version, node_name}
  ▼
RECV_STATUS
  │  recv: status_msg
  │  assert status == "ok" | "ok_simultaneous"
  ▼
RECV_CHALLENGE
  │  recv: challenge_msg {flags, challenge, creation, node_name}
  │  digest = md5(cookie ++ challenge_as_string)
  ▼
SEND_CHALLENGE_REPLY
  │  send: challenge_reply {our_challenge, digest}
  ▼
RECV_CHALLENGE_ACK
  │  recv: challenge_ack {digest}
  │  verify: digest == md5(cookie ++ our_challenge_as_string)
  ▼
CONNECTED
```

#### 5.2.2 Capability Flags

zbeam MUST advertise and respect these distribution flags:

| Flag | Hex | Meaning |
|---|---|---|
| `DFLAG_EXTENDED_REFERENCES` | 0x4 | 82-bit references |
| `DFLAG_DIST_MONITOR` | 0x8 | Monitor support |
| `DFLAG_EXTENDED_PIDS_PORTS` | 0x100 | Longer PIDs |
| `DFLAG_NEW_FLOATS` | 0x2000 | IEEE 754 float encoding |
| `DFLAG_UTF8_ATOMS` | 0x10000 | UTF-8 atoms |
| `DFLAG_MAP_TAG` | 0x20000 | Map term support |
| `DFLAG_BIG_CREATION` | 0x40000 | 32-bit creation |
| `DFLAG_HANDSHAKE_23` | 0x1000000 | OTP 23+ handshake |
| `DFLAG_UNLINK_ID` | 0x2000000 | Unlink with ID |

#### 5.2.3 Zig Interface

```zig
pub const HandshakeFsm = struct {
    pub const Role = enum { initiating, accepting };
    pub const HandshakeResult = struct {
        peer_name: []const u8,
        peer_flags: DistFlags,
        peer_creation: u32,
    };

    pub fn perform(
        stream: std.net.Stream,
        role: Role,
        our_name: []const u8,
        cookie: []const u8,
        our_flags: DistFlags,
    ) !HandshakeResult;
};
```

---

### 5.3 ETF — External Term Format

**Reference**: [ETF Specification](https://www.erlang.org/doc/apps/erts/erl_ext_dist.html)

#### 5.3.1 Supported Term Tags

zbeam MUST support encoding and decoding of all the following tags:

| Tag | Byte | Type |
|---|---|---|
| `ATOM_CACHE_REF` | 82 | Cached atom reference |
| `SMALL_INTEGER_EXT` | 97 | 8-bit unsigned integer |
| `INTEGER_EXT` | 98 | 32-bit signed integer |
| `FLOAT_EXT` | 99 | Legacy float (deprecated) |
| `ATOM_EXT` | 100 | Atom (ISO-8859-1) |
| `REFERENCE_EXT` | 101 | Reference |
| `PORT_EXT` | 102 | Port |
| `PID_EXT` | 103 | Process identifier |
| `SMALL_TUPLE_EXT` | 104 | Tuple ≤ 255 elements |
| `LARGE_TUPLE_EXT` | 105 | Tuple > 255 elements |
| `MAP_EXT` | 116 | Map |
| `NIL_EXT` | 106 | Empty list |
| `STRING_EXT` | 107 | Character list (optimized) |
| `LIST_EXT` | 108 | Proper/improper list |
| `BINARY_EXT` | 109 | Binary |
| `SMALL_BIG_EXT` | 110 | Bignum ≤ 255 digits |
| `LARGE_BIG_EXT` | 111 | Bignum > 255 digits |
| `NEW_REFERENCE_EXT` | 114 | Multi-word reference |
| `SMALL_ATOM_EXT` | 115 | Atom (ISO-8859-1) ≤ 255 |
| `NEW_PID_EXT` | 88 | PID with 32-bit creation |
| `NEW_PORT_EXT` | 89 | Port with 32-bit creation |
| `NEWER_REFERENCE_EXT` | 90 | Reference with 32-bit creation |
| `SMALL_ATOM_UTF8_EXT` | 119 | UTF-8 atom ≤ 255 bytes |
| `ATOM_UTF8_EXT` | 118 | UTF-8 atom |
| `NEW_FLOAT_EXT` | 70 | IEEE 754 float (64-bit) |
| `BIT_BINARY_EXT` | 77 | Bitstring |
| `ATOM_CACHE_REF` | 82 | Distribution atom cache |
| `LOCAL_EXT` | 121 | Local term (node-internal) |

All encoded terms MUST begin with version byte `131` (0x83).

#### 5.3.2 Comptime Type Mapping — Encoder

zbeam uses `comptime` reflection to generate ETF encoders for Zig types with zero runtime overhead:

```zig
pub fn encode(comptime T: type, value: T, writer: anytype) !void {
    try writer.writeByte(131); // version magic
    try encodeValue(T, value, writer);
}

fn encodeValue(comptime T: type, value: T, writer: anytype) !void {
    switch (@typeInfo(T)) {
        .Int => |info| {
            if (info.bits <= 8 and info.signedness == .unsigned) {
                try writer.writeByte(97); // SMALL_INTEGER_EXT
                try writer.writeByte(@intCast(value));
            } else {
                try writer.writeByte(98); // INTEGER_EXT
                try writer.writeInt(i32, @intCast(value), .big);
            }
        },
        .Float => {
            try writer.writeByte(70); // NEW_FLOAT_EXT
            try writer.writeAll(&std.mem.toBytes(@as(f64, value)));
        },
        .Struct => |info| {
            // Struct encodes as ETF tuple — fields in declaration order
            try writer.writeByte(104); // SMALL_TUPLE_EXT
            try writer.writeByte(info.fields.len);
            inline for (info.fields) |field| {
                try encodeValue(field.type, @field(value, field.name), writer);
            }
        },
        .Optional => |info| {
            if (value) |inner| {
                try encodeValue(info.child, inner, writer);
            } else {
                try encodeAtom("undefined", writer);
            }
        },
        else => @compileError("Unsupported type for ETF encoding: " ++ @typeName(T)),
    }
}
```

#### 5.3.3 Comptime Type Mapping — Decoder

The decoder is the symmetric counterpart of the encoder. It MUST exist in two modes:

**Mode 1 — Comptime typed decode**: when the expected Zig type is known at compile time. Zero runtime overhead, fails at decode-time if wire type does not match expected Zig type.

```zig
pub fn decode(comptime T: type, reader: anytype) !T {
    const version = try reader.readByte();
    if (version != 131) return error.InvalidVersion;
    return decodeValue(T, reader);
}

fn decodeValue(comptime T: type, reader: anytype) !T {
    const tag = try reader.readByte();
    switch (@typeInfo(T)) {
        .Int => {
            return switch (tag) {
                97  => @intCast(try reader.readByte()),           // SMALL_INTEGER_EXT
                98  => @intCast(try reader.readInt(i32, .big)),   // INTEGER_EXT
                110 => decodeSmallBig(T, reader),                 // SMALL_BIG_EXT
                else => error.TypeMismatch,
            };
        },
        .Float => {
            return switch (tag) {
                70 => @bitCast(try reader.readInt(u64, .big)),    // NEW_FLOAT_EXT
                else => error.TypeMismatch,
            };
        },
        .Bool => {
            // Erlang booleans are atoms 'true' / 'false'
            if (tag != 119 and tag != 115 and tag != 100) return error.TypeMismatch;
            const atom = try decodeAtomBytes(reader, tag);
            if (std.mem.eql(u8, atom, "true")) return true;
            if (std.mem.eql(u8, atom, "false")) return false;
            return error.TypeMismatch;
        },
        .Struct => |info| {
            // Expect tuple with same arity as struct fields
            const arity = switch (tag) {
                104 => try reader.readByte(),                         // SMALL_TUPLE_EXT
                105 => @as(u8, @intCast(try reader.readInt(u32, .big))), // LARGE_TUPLE_EXT
                else => return error.TypeMismatch,
            };
            if (arity != info.fields.len) return error.ArityMismatch;
            var result: T = undefined;
            inline for (info.fields) |field| {
                @field(result, field.name) = try decodeValue(field.type, reader);
            }
            return result;
        },
        .Optional => |info| {
            // Peek if it's atom 'undefined' — treat as null
            if (tag == 119 or tag == 115 or tag == 100) {
                const atom = try decodeAtomBytes(reader, tag);
                if (std.mem.eql(u8, atom, "undefined")) return null;
            }
            // Not undefined — decode as inner type
            return try decodeValueWithTag(info.child, reader, tag);
        },
        else => @compileError("Unsupported type for ETF decoding: " ++ @typeName(T)),
    }
}
```

**Mode 2 — Runtime dynamic decode (gradual fallback)**: used when the message shape is unknown. Decodes into `Term` union, inspectable at runtime. All allocations go into a provided allocator (arena scoped to message lifetime):

```zig
pub const Term = union(enum) {
    integer: i64,
    float:   f64,
    atom:    Atom,           // interned — points into atom table
    binary:  BinaryView,     // zero-copy — points into recv buffer
    pid:     RawPid,
    ref:     RawRef,
    tuple:   []Term,         // allocated in message arena
    list:    []Term,
    map:     []KV,
    nil,
    boolean: bool,

    pub const KV = struct { key: Term, value: Term };
};

pub fn decodeDynamic(reader: anytype, arena: std.mem.Allocator) !Term {
    const version = try reader.readByte();
    if (version != 131) return error.InvalidVersion;
    return decodeDynamicValue(reader, arena);
}

fn decodeDynamicValue(reader: anytype, arena: std.mem.Allocator) !Term {
    const tag = try reader.readByte();
    return switch (tag) {
        97  => .{ .integer = try reader.readByte() },
        98  => .{ .integer = try reader.readInt(i32, .big) },
        70  => .{ .float   = @bitCast(try reader.readInt(u64, .big)) },
        106 => .nil,
        104, 105 => blk: {
            const arity: u32 = if (tag == 104)
                try reader.readByte()
            else
                try reader.readInt(u32, .big);
            const elements = try arena.alloc(Term, arity);
            for (elements) |*el| el.* = try decodeDynamicValue(reader, arena);
            break :blk .{ .tuple = elements };
        },
        108 => blk: {
            const length = try reader.readInt(u32, .big);
            const elements = try arena.alloc(Term, length);
            for (elements) |*el| el.* = try decodeDynamicValue(reader, arena);
            _ = try decodeDynamicValue(reader, arena); // tail (NIL for proper list)
            break :blk .{ .list = elements };
        },
        109 => blk: {
            const length = try reader.readInt(u32, .big);
            const bytes = try reader.readBytesNoEof(length); // zero-copy view
            break :blk .{ .binary = .{ .bytes = bytes } };
        },
        116 => blk: {
            const count = try reader.readInt(u32, .big);
            const pairs = try arena.alloc(Term.KV, count);
            for (pairs) |*pair| {
                pair.key   = try decodeDynamicValue(reader, arena);
                pair.value = try decodeDynamicValue(reader, arena);
            }
            break :blk .{ .map = pairs };
        },
        88  => .{ .pid = try decodeNewPid(reader) },   // NEW_PID_EXT
        90  => .{ .ref = try decodeNewerRef(reader) },  // NEWER_REFERENCE_EXT
        119, 115, 100 => blk: {
            const atom = try decodeAtomInterned(reader, tag);
            // Recognize booleans at decode time
            if (atom.eql("true"))  break :blk .{ .boolean = true };
            if (atom.eql("false")) break :blk .{ .boolean = false };
            break :blk .{ .atom = atom };
        },
        else => error.UnknownTag,
    };
}
```

**Decode strategy selection rule**: zbeam MUST use Mode 1 for all known message shapes (control messages, gen_server call/reply). Mode 2 is reserved for user-facing message handlers that receive `Term`.

#### 5.3.4 Zero-Copy Binary — Lifetime Rules

For `[]const u8` values, zbeam MUST use `BINARY_EXT` and SHOULD reference the original recv buffer (zero-copy):

```zig
pub const BinaryView = struct {
    // Borrows from the per-message arena's recv buffer.
    // VALID only for the duration of the current message handler call.
    // INVALID after: actor calls receive() again, or after handler returns.
    bytes: []const u8,

    // Call this if the binary must outlive the current message scope.
    pub fn toOwned(self: BinaryView, allocator: std.mem.Allocator) ![]u8 {
        return allocator.dupe(u8, self.bytes);
    }
};
```

**Lifetime violation is a logic error, not a safety issue** (Zig is memory-safe here because the arena is not freed until the connection dies). However, the data pointed to by `BinaryView.bytes` MAY be overwritten by the next recv. Rule: if you call `receive()` again or store the binary for later, call `toOwned()` first.

#### 5.3.5 Atom Interning & Cache

The atom intern table is global and process-scoped. Each per-connection atom cache is connection-scoped (2048 slots, invalidated on reconnect):

```zig
// Global atom table — string → interned Atom id
pub const AtomTable = struct {
    table: std.StringHashMap(Atom),
    mutex: std.Thread.Mutex,

    pub fn intern(self: *AtomTable, bytes: []const u8) !Atom {
        self.mutex.lock();
        defer self.mutex.unlock();
        const result = try self.table.getOrPut(bytes);
        if (!result.found_existing) {
            result.value_ptr.* = Atom{ .id = self.table.count() - 1 };
        }
        return result.value_ptr.*;
    }

    pub fn lookup(self: *AtomTable, atom: Atom) []const u8 {
        // Reverse lookup — O(n) acceptable, atoms rarely looked up by id
        var it = self.table.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.id == atom.id) return entry.key_ptr.*;
        }
        unreachable; // atom ids are only created by intern()
    }
};

// Per-connection cache — maps cache_index (0–2047) to interned Atom
pub const AtomCache = struct {
    slots: [2048]?Atom = [_]?Atom{null} ** 2048,

    pub fn get(self: *const AtomCache, index: u11) ?Atom {
        return self.slots[index];
    }

    pub fn put(self: *AtomCache, index: u11, atom: Atom) void {
        self.slots[index] = atom;
    }

    pub fn reset(self: *AtomCache) void {
        @memset(&self.slots, null);
    }
};
```

#### 5.3.6 PID & Ref Generation

zbeam PIDs MUST comply with BEAM's `NEW_PID_EXT` format and be unique within the node's lifetime:

```zig
// NEW_PID_EXT wire format:
// node_atom: atom (node name)
// id:        u32 (local process id — monotonically increasing, wraps at 2^28)
// serial:    u32 (increments each time id wraps)
// creation:  u32 (from EPMD ALIVE2_RESP — unique per node registration)

pub const PidGenerator = struct {
    id:       std.atomic.Value(u32),
    serial:   std.atomic.Value(u32),
    creation: u32, // set once at EPMD registration, never changes

    pub fn next(self: *PidGenerator) RawPid {
        const raw = self.id.fetchAdd(1, .monotonic);
        const pid_id = raw & 0x0FFFFFFF; // BEAM uses 28 bits for id
        const serial = if (pid_id == 0 and raw != 0)
            self.serial.fetchAdd(1, .monotonic)
        else
            self.serial.load(.monotonic);
        return .{ .id = pid_id, .serial = serial, .creation = self.creation };
    }
};

// NEWER_REFERENCE_EXT: node_atom + creation:u32 + id:[3]u32 (96 bits total)
pub const RefGenerator = struct {
    counter: std.atomic.Value(u64),
    creation: u32,

    pub fn next(self: *RefGenerator) RawRef {
        const n = self.counter.fetchAdd(1, .monotonic);
        return .{
            .creation = self.creation,
            .words    = .{ @intCast(n & 0xFFFFFFFF), @intCast(n >> 32), 0 },
        };
    }
};
```

---

### 5.4 Distribution Protocol Layer

**Reference**: [EDP Message Format](https://www.erlang.org/doc/apps/erts/erl_dist_protocol.html#protocol-between-connected-nodes)

#### 5.4.1 Message Framing

After handshake, all messages are framed as:

```
4 bytes : length (big-endian u32) — byte count of everything after this field
1 byte  : pass-through tag = 112 (0x70)
[atom cache header — optional, present if flag indicates]
ETF term : control message
[ETF term : payload — only for SEND, REG_SEND]
```

#### 5.4.2 Control Messages

zbeam MUST handle these control message types (tuple tag is first element):

| Tag | Tuple | Direction |
|---|---|---|
| 1 | `{LINK, from_pid, to_pid}` | Both |
| 2 | `{SEND, unused, to_pid}` + payload | Recv |
| 3 | `{EXIT, from_pid, to_pid, reason}` | Both |
| 4 | `{UNLINK, from_pid, to_pid}` | Both |
| 6 | `{REG_SEND, from_pid, unused, to_name}` + payload | Both |
| 7 | `{GROUP_LEADER, from_pid, to_pid}` | Both |
| 8 | `{EXIT2, from_pid, to_pid, reason}` | Both |
| 19 | `{MONITOR_P, from_pid, to_pid_or_name, ref}` | Both |
| 20 | `{DEMONITOR_P, from_pid, to_pid_or_name, ref}` | Both |
| 21 | `{MONITOR_P_EXIT, from_pid, to_pid, ref, reason}` | Both |
| 35 | `{UNLINK_ID, id, from_pid, to_pid}` | Both |
| 36 | `{UNLINK_ID_ACK, id, from_pid, to_pid}` | Both |

#### 5.4.3 Heartbeat / Tick

BEAM sends a tick (4 zero bytes) every ~15 seconds. zbeam MUST:

1. Respond to ticks within 60 seconds or the peer will disconnect.
2. Independently send ticks every 15 seconds.

#### 5.4.4 Fragment Reassembly

For large messages (> ~64KB), BEAM uses fragmented distribution messages. zbeam MUST implement:

```
4 bytes: length
8 bytes: sequence_id (first fragment has bit 63 set)
8 bytes: fragment_id  (1 = last fragment)
payload
```

#### 5.4.5 Fragment Reassembly — Complete Algorithm

Large messages from BEAM arrive as multiple frames. zbeam MUST reassemble them before ETF decode. The reassembly state machine operates per-connection:

**Wire format per fragment frame**:
```
4 bytes : length (big-endian u32) — covers everything below
1 byte  : pass-through tag = 112 (0x70)
8 bytes : sequence_id — bit 63 SET on first fragment, CLEAR on continuation
8 bytes : fragment_id  — monotonically increasing per sequence; value 1 = LAST fragment
N bytes : payload chunk
```

**State machine**:

```zig
pub const FragmentReassembler = struct {
    // Per-sequence in-progress assembly buffer
    const Assembly = struct {
        sequence_id:    u64,
        buf:            std.ArrayList(u8),
        last_fragment:  u64,  // fragment_id of the last fragment (set on arrival of last)
        received_count: u64,
    };

    in_progress: std.AutoHashMap(u64, Assembly),
    allocator:   std.mem.Allocator,

    // Called for every incoming frame. Returns complete message when reassembly done.
    pub fn feed(
        self: *FragmentReassembler,
        io:   std.Io,
        raw_sequence_id: u64,
        fragment_id:     u64,
        payload:         []const u8,
    ) !?[]const u8 {
        const is_first   = (raw_sequence_id >> 63) == 1;
        const sequence_id = raw_sequence_id & ~(@as(u64, 1) << 63);
        const is_last    = (fragment_id == 1);

        if (is_first) {
            // Start new assembly — sequence_id MUST NOT already be in-progress
            if (self.in_progress.contains(sequence_id)) return error.DuplicateSequenceId;
            var asm_buf = std.ArrayList(u8).init(self.allocator);
            try asm_buf.appendSlice(payload);
            try self.in_progress.put(sequence_id, .{
                .sequence_id    = sequence_id,
                .buf            = asm_buf,
                .last_fragment  = if (is_last) fragment_id else 0,
                .received_count = 1,
            });
        } else {
            // Continuation — sequence MUST already exist
            const entry = self.in_progress.getPtr(sequence_id) orelse
                return error.UnknownSequenceId;
            try entry.buf.appendSlice(payload);
            entry.received_count += 1;
            if (is_last) entry.last_fragment = fragment_id;
        }

        // Check if complete: last fragment received AND received_count == last_fragment
        const entry = self.in_progress.getPtr(sequence_id).?;
        if (entry.last_fragment != 0 and entry.received_count == entry.last_fragment) {
            const complete = try entry.buf.toOwnedSlice();
            _ = self.in_progress.remove(sequence_id);
            return complete; // caller owns this slice
        }
        return null; // not yet complete
    }

    // Call periodically to expire stale in-progress assemblies (prevents memory leak).
    // Sequences older than timeout_ns are dropped.
    pub fn expireStale(self: *FragmentReassembler, timeout_ns: u64) void {
        _ = timeout_ns;
        // Implementation: timestamp each Assembly at creation, sweep on expiry.
        // Stale sequences: send no signal — peer is assumed disconnected.
    }
};
```

**Invariants**:
- A sequence with `last_fragment = 1` and `received_count = 1` is a single-fragment message — MUST be treated identically to a non-fragmented message.
- `sequence_id` values MUST be unique per connection per session. Reuse after reconnect is acceptable (atom cache is reset).
- If `received_count > last_fragment`, the connection is in a corrupted state — MUST disconnect and trigger `onDisconnect`.

zbeam MUST reassemble fragments before passing to the ETF decoder.

---

### 5.5 Actor Runtime

The zbeam actor runtime provides the abstraction that makes Zig code appear as BEAM processes. It is built directly on `std.Io` (Zig 0.16) — the pluggable I/O interface that separates blocking-style code from the underlying execution model (threaded, evented/io_uring, or custom backend).

**Critical design constraint**: All actor code is written as if it is synchronous/blocking. `std.Io` ensures it runs as async/evented without function coloring — actor function signatures do NOT change based on execution model.

#### 5.5.1 Actor Identity

Each actor has an opaque identity composed of:

```zig
pub const Pid = struct {
    // Phantom type — cannot be constructed by user code
    node: NodeName,  // "zbeam@host"
    id: u32,         // local actor id
    serial: u32,
    creation: u32,   // from EPMD ALIVE2_RESP

    pub fn toEtf(self: Pid, writer: anytype) !void { ... }
};
```

PID values MUST be constructed only by the actor runtime. User code receives `Pid` as an opaque capability — it can send to it and monitor it, but cannot inspect or forge fields.

#### 5.5.2 I/O Model: std.Io as Runtime Backend

zbeam REQUIRES `std.Io` (Zig 0.16) as its I/O abstraction. All network I/O — TCP connections to peers, EPMD, incoming connection listener — MUST go through an `std.Io` instance passed at startup:

```zig
pub fn start(io: std.Io, config: NodeConfig) !Node {
    // io is passed down to all subsystems
    // caller chooses backend: std.Io.Threaded, std.Io.Evented, or custom
}
```

The caller decides the execution backend. zbeam itself is backend-agnostic.

#### 5.5.3 Concurrent Actor Spawn via Io.Group

Each incoming connection from a BEAM peer, and each spawned actor, runs as a concurrent task managed via `std.Io.Group`. This is the correct 0.16 API — NOT thread spawning directly:

```zig
pub const ActorRuntime = struct {
    io: std.Io,
    group: std.Io.Group,

    pub fn init(io: std.Io) ActorRuntime {
        return .{ .io = io, .group = .init };
    }

    pub fn spawn(
        self: *ActorRuntime,
        comptime handler: fn (io: std.Io, ctx: ActorContext) anyerror!void,
        init_args: anytype,
    ) !Pid {
        const pid = registry.allocPid();
        // io.concurrent: runs handler as a concurrent task in the group
        // looks synchronous — executed async by the Io backend
        try self.group.concurrent(self.io, handler, .{ self.io, ActorContext{
            .pid = pid,
            .args = init_args,
        }});
        return pid;
    }

    pub fn wait(self: *ActorRuntime) void {
        // Wait for all actors in group to complete
        defer self.group.cancel(self.io);
    }
};
```

#### 5.5.4 Actor Body & Receive

Actor handlers are plain Zig functions — no special keywords, no `async` annotation. They block on `receive` which suspends the task cooperatively via `std.Io`:

```zig
// Actor handler — written as synchronous code
fn myActor(io: std.Io, ctx: ActorContext) !void {
    while (true) {
        // blocks until message arrives — std.Io handles cooperative suspend
        const msg = try ctx.mailbox.receive(io);

        switch (msg) {
            .compute => |data| {
                const result = heavyCompute(data);
                try ctx.send(io, msg.from, .{ .result, result });
            },
            .stop => break,
        }
    }
}
```

`mailbox.receive(io)` internally uses `std.Io.Event` to wait without blocking the OS thread — the `io` backend decides how to schedule the wait.

#### 5.5.5 Background I/O via io.async

For operations that should run while the actor does other work (e.g., sending a message while waiting for another):

```zig
fn actorWithBackground(io: std.Io, ctx: ActorContext) !void {
    // Fire-and-forget dist send while continuing to process
    var send_future = io.async(distSend, .{ io, peer_conn, encoded_msg });
    defer send_future.cancel(io) catch {};

    // Do other work while send runs
    const next_msg = try ctx.mailbox.receive(io);

    // Await the send result
    try send_future.await(io);
    _ = next_msg;
}
```

#### 5.5.6 Connection Listener

The dist connection listener uses `io.concurrent` inside a loop — the canonical 0.16 pattern:

```zig
fn runListener(io: std.Io, server: std.net.Server) !void {
    var group: std.Io.Group = .init;
    defer group.cancel(io);

    while (true) {
        const stream = try server.accept(io);
        errdefer stream.close(io);
        // Each peer connection runs as concurrent task
        try group.concurrent(io, handlePeerConnection, .{ io, stream });
    }
}
```

#### 5.5.7 Reduction Accounting

`std.Io` does not natively count BEAM-style reductions. zbeam adds a lightweight reduction counter via comptime instrumentation on hot paths (ETF decode loops, message dispatch):

```zig
pub const REDUCTION_BUDGET: usize = 2000;

// Injected by comptime wrapper at ETF decode loop sites
pub inline fn checkReductions(io: std.Io, counter: *usize) !void {
    counter.* += 1;
    if (counter.* >= REDUCTION_BUDGET) {
        counter.* = 0;
        // Cooperative yield back to Io scheduler
        try io.yield();
    }
}
```

`io.yield()` is the correct 0.16 API to yield a concurrent task — NOT a manual `@call` or stack switch.
#### 5.5.8 Mailbox

Each actor owns a mailbox backed by `std.Io.Event` for zero-busy-wait notification:

```zig
pub const Mailbox = struct {
    queue: std.fifo.LinearFifo(Term, .Dynamic),
    event: std.Io.Event,
    mutex: std.Thread.Mutex,

    pub fn deliver(self: *Mailbox, msg: Term) !void {
        self.mutex.lock();
        try self.queue.writeItem(msg);
        self.mutex.unlock();
        self.event.set();
    }

    pub fn receive(self: *Mailbox, io: std.Io) !Term {
        while (true) {
            self.mutex.lock();
            if (self.queue.count > 0) {
                const msg = self.queue.readItem().?;
                self.mutex.unlock();
                return msg;
            }
            self.mutex.unlock();
            try self.event.wait(io);
            self.event.reset();
        }
    }
};
```

#### 5.5.9 Link & Monitor Tables

```zig
const LinkTable = std.AutoHashMap(Pid, std.ArrayListUnmanaged(Pid));
const MonitorTable = std.AutoHashMap(Ref, MonitorEntry);

pub const MonitorEntry = struct {
    watcher: Pid,
    watched: Pid,
    ref: Ref,
};
```

When a zbeam actor exits (normally or abnormally):
1. All entries in `link_table[pid]` receive `EXIT` signal via dist.
2. All entries in `monitor_table` where `watched == pid` receive `MONITOR_P_EXIT` via dist.

---

### 5.6 Name Registry

The Name Registry maps atom names to local actor PIDs. It is the mechanism by which BEAM nodes can address zbeam actors by name (e.g., `{:my_actor, :"zbeam@host"}`).

#### 5.6.1 Interface

```zig
pub const Registry = struct {
    table: std.StringHashMap(Pid),
    mutex: std.Thread.Mutex,

    // Register name → pid. Returns error.AlreadyRegistered if name is taken.
    pub fn register(self: *Registry, name: Atom, pid: Pid) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        const result = try self.table.getOrPut(name.bytes());
        if (result.found_existing) return error.AlreadyRegistered;
        result.value_ptr.* = pid;
    }

    // Unregister by name. Silent if name not found (idempotent).
    pub fn unregister(self: *Registry, name: Atom) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        _ = self.table.remove(name.bytes());
    }

    // Unregister by pid — called automatically on actor exit.
    pub fn unregisterPid(self: *Registry, pid: Pid) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        var it = self.table.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.eql(pid)) {
                _ = self.table.remove(entry.key_ptr.*);
                return;
            }
        }
    }

    // Lookup pid by name. Returns null if not registered.
    pub fn whereis(self: *Registry, name: Atom) ?Pid {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.table.get(name.bytes());
    }

    // Returns list of all registered names (for introspection / :sys.status).
    pub fn registeredNames(self: *Registry, allocator: std.mem.Allocator) ![]Atom {
        self.mutex.lock();
        defer self.mutex.unlock();
        var names = try allocator.alloc(Atom, self.table.count());
        var it = self.table.keyIterator();
        var i: usize = 0;
        while (it.next()) |key| {
            names[i] = try Atom.fromBytes(key.*);
            i += 1;
        }
        return names;
    }
};
```

#### 5.6.2 Lifecycle Rules

1. An actor MAY register itself during initialization via `Effects.Register`.
2. When an actor exits (any reason), the runtime MUST call `registry.unregisterPid(pid)` before sending EXIT signals to linked processes.
3. A name MUST be unregistered before it can be re-registered by another actor.
4. `REG_SEND` control messages from BEAM (sending to a named process) MUST be resolved via `registry.whereis()` before delivery. If name is not found, MUST send `{:badarg}` error term back to sender.

---

### 5.7 Effect Channel

The Effect Channel is the typed interface between actor logic and the outside world. It enforces that all I/O is declared as capabilities — actors cannot perform arbitrary I/O.

```zig
pub const Effects = struct {
    pub const Send = struct {
        pub fn call(capability: SendCap, to: Pid, message: anytype) !void;
    };
    pub const Spawn = struct {
        pub fn call(capability: SpawnCap, comptime handler: anytype, args: anytype) !Pid;
    };
    pub const Monitor = struct {
        pub fn call(capability: MonitorCap, target: Pid) !Ref;
    };
    pub const Register = struct {
        pub fn call(capability: RegisterCap, name: Atom, pid: Pid) !void;
    };
};
```

Capabilities are passed to actor `init` by the runtime and cannot be forged. An actor that is not granted `SpawnCap` cannot spawn children.

---

## 6. NodeConfig & Public API

### 6.1 NodeConfig

`NodeConfig` is the complete configuration struct passed to `zbeam.start()`. Every field MUST have a documented default. No field may be `undefined` at start time.

```zig
pub const NodeConfig = struct {
    // --- Identity ---
    // Full node name including host. Format: "name@host".
    // MUST match [a-zA-Z0-9_]+@[a-zA-Z0-9._-]+
    node_name: []const u8,

    // Erlang magic cookie for authentication.
    // Read from ~/.erlang.cookie if not provided (not implemented in MVP — must be explicit).
    cookie: []const u8,

    // --- Network ---
    // Port zbeam listens on for incoming dist connections.
    // 0 = OS assigns a random port (recommended for development).
    listen_port: u16 = 0,

    // EPMD host. Default: 127.0.0.1
    epmd_host: []const u8 = "127.0.0.1",

    // EPMD port. Default: 4369 (standard).
    epmd_port: u16 = 4369,

    // --- Limits ---
    // Maximum incoming message size in bytes. Prevents memory exhaustion.
    // Default: 128 MiB (134_217_728 bytes)
    max_message_size: u32 = 134_217_728,

    // Maximum number of concurrent actor tasks.
    // Default: 65536
    max_actors: u32 = 65_536,

    // Maximum mailbox depth per actor (messages). 0 = unbounded.
    // Default: 0 (unbounded — caller is responsible for backpressure)
    mailbox_max_depth: u32 = 0,

    // --- Scheduler ---
    // Reduction budget per actor scheduling quantum.
    // Matches BEAM default. Lower = more preemptive, higher = more throughput.
    // Default: 2000
    reduction_budget: u32 = 2_000,

    // --- Reconnect ---
    // Minimum backoff for reconnecting to a disconnected peer (milliseconds).
    reconnect_backoff_min_ms: u32 = 500,

    // Maximum backoff (milliseconds). Exponential backoff caps at this value.
    reconnect_backoff_max_ms: u32 = 30_000,

    // Maximum reconnect attempts. 0 = infinite.
    reconnect_max_attempts: u32 = 0,
};
```

### 6.2 Public API

The complete public surface of `zbeam`:

```zig
// Start the node. Registers with EPMD, starts listener, returns Node handle.
// Caller owns the Node — must call node.shutdown() to clean up.
pub fn start(io: std.Io, allocator: std.mem.Allocator, config: NodeConfig) !Node;

pub const Node = struct {
    // Spawn a named actor. Actor is immediately addressable by name from BEAM.
    pub fn spawnNamed(
        self: *Node,
        name: []const u8,
        comptime handler: fn (std.Io, ActorContext) anyerror!void,
        args: anytype,
    ) !Pid;

    // Spawn an anonymous actor. Only addressable via returned Pid.
    pub fn spawn(
        self: *Node,
        comptime handler: fn (std.Io, ActorContext) anyerror!void,
        args: anytype,
    ) !Pid;

    // Send a message to a local actor by Pid.
    pub fn send(self: *Node, io: std.Io, to: Pid, message: anytype) !void;

    // Send a message to a local actor by registered name.
    pub fn sendNamed(self: *Node, io: std.Io, name: []const u8, message: anytype) !void;

    // Lookup registered actor by name. Returns null if not registered.
    pub fn whereis(self: *Node, name: []const u8) ?Pid;

    // Graceful shutdown. Blocks until all actors exit and EPMD is unregistered.
    pub fn shutdown(self: *Node, io: std.Io) void;

    // Node name as registered with EPMD.
    pub fn name(self: *const Node) []const u8;
};

pub const ActorContext = struct {
    pid:     Pid,
    mailbox: *Mailbox,
    // Capabilities — injected by runtime, cannot be forged by user code
    caps: struct {
        send:     SendCap,
        spawn:    SpawnCap,
        monitor:  MonitorCap,
        register: RegisterCap,
    },
};
```

---

## 7. Node Lifecycle (Start / Shutdown)

### 7.1 Startup Sequence

```
zbeam.start(io, allocator, config)
  │
  ├─ 1. Validate NodeConfig
  │       node_name format, cookie non-empty, ports in valid range
  │       → error.InvalidConfig if any field fails
  │
  ├─ 2. Bind TCP listener
  │       std.net.Address.listen(io, listen_port)
  │       → error.AddressInUse if port taken
  │       → actual_port = listener.listen_address.getPort()
  │
  ├─ 3. Register with EPMD
  │       EpmdClient.register(io, node_short_name, actual_port)
  │       → error.EpmdUnavailable if EPMD not running
  │       → creation = result.creation (store in PidGenerator)
  │
  ├─ 4. Initialize subsystems
  │       AtomTable, Registry, LinkTable, MonitorTable, PidGenerator, RefGenerator
  │       ActorRuntime (Io.Group: actor_group)
  │
  ├─ 5. Start listener task
  │       actor_group.concurrent(io, runListener, .{ io, listener })
  │
  └─ 6. Return Node handle
```

### 7.2 Shutdown Sequence

`node.shutdown(io)` MUST execute in this exact order:

```
node.shutdown(io)
  │
  ├─ 1. Set node_state = .shutting_down
  │       New incoming connections are rejected immediately after accept.
  │
  ├─ 2. Cancel actor_group
  │       group.cancel(io) — signals all actor tasks to stop.
  │       Each actor that is blocked on mailbox.receive(io) will get
  │       a synthetic .shutdown message injected before cancel.
  │
  ├─ 3. Send EXIT to all linked remote PIDs
  │       Reason: atom 'shutdown'
  │       Sent over existing dist connections before they close.
  │
  ├─ 4. Send MONITOR_P_EXIT to all remote monitors
  │       Reason: atom 'shutdown'
  │
  ├─ 5. Cancel connection_group
  │       All dist TCP connections closed.
  │
  ├─ 6. Unregister from EPMD
  │       Close the EPMD registration TCP connection.
  │       EPMD detects close and removes the node from its table.
  │
  └─ 7. Free all subsystem memory
        AtomTable, Registry, LinkTable, MonitorTable, arena allocators.
```

### 7.3 Actor Panic Containment

Every actor task MUST be wrapped in a catch-all error handler by the runtime — user handler code MUST NOT be able to crash the node:

```zig
fn actorWrapper(
    io: std.Io,
    runtime: *ActorRuntime,
    handler: fn (std.Io, ActorContext) anyerror!void,
    ctx: ActorContext,
) void {
    handler(io, ctx) catch |err| {
        // Actor exited with error — treat as abnormal exit
        const reason = errorToAtom(err); // e.g., error.OutOfMemory → :out_of_memory
        runtime.onActorExit(ctx.pid, .{ .abnormal = reason });
    };
    // Normal return — treat as normal exit
    runtime.onActorExit(ctx.pid, .normal);
}

fn onActorExit(self: *ActorRuntime, pid: Pid, reason: ExitReason) void {
    self.registry.unregisterPid(pid);
    self.sendExitToLinks(pid, reason);
    self.sendDownToMonitors(pid, reason);
}
```

`@panic` from user code — if it occurs — is caught by Zig's panic handler at the OS level. To prevent node crash, zbeam SHOULD configure a custom panic handler via `std.debug.panicImpl` that logs and marks the actor as crashed without aborting the process. This is a best-effort safety net; correct actor code should use error unions.

---

## 8. Dist Connection Pool & Reconnect FSM

### 8.1 Connection States

Each peer connection is modeled as a finite state machine:

```
          ┌──────────────────────────────────────────────┐
          │                                              │
          ▼                                              │
       IDLE                                             │
          │  connect_request or incoming_accept          │
          ▼                                             │
     HANDSHAKING                                        │
          │  handshake success                           │
          ▼                                             │
      CONNECTED ─── peer_disconnect / error ──► DISCONNECTED
          │                                              │
          │  node.shutdown()                             │  backoff_expired + attempt < max
          ▼                                             │
       CLOSING                                          │
                                                        ▼
                                                   RECONNECTING
                                                        │
                                                        │ handshake success
                                                        ▼
                                                    CONNECTED
```

### 8.2 Connection State Machine

```zig
pub const ConnectionState = enum {
    idle,
    handshaking,
    connected,
    disconnected,
    reconnecting,
    closing,
};

pub const PeerConnection = struct {
    peer_name:    []const u8,
    state:        ConnectionState,
    stream:       ?std.net.Stream,
    atom_cache:   AtomCache,
    send_buf:     std.ArrayList(u8),

    // Reconnect state
    attempt:      u32,
    backoff_ms:   u32,

    pub fn onDisconnect(self: *PeerConnection, io: std.Io, config: NodeConfig) void {
        self.stream = null;
        self.atom_cache.reset(); // MUST reset atom cache on disconnect
        self.state = .disconnected;
        if (config.reconnect_max_attempts == 0 or
            self.attempt < config.reconnect_max_attempts)
        {
            self.scheduleReconnect(io, config);
        }
    }

    fn scheduleReconnect(self: *PeerConnection, io: std.Io, config: NodeConfig) void {
        // Exponential backoff with jitter
        const jitter = std.crypto.random.int(u32) % (self.backoff_ms / 4 + 1);
        const wait_ms = @min(self.backoff_ms + jitter, config.reconnect_backoff_max_ms);
        self.backoff_ms = @min(self.backoff_ms * 2, config.reconnect_backoff_max_ms);
        self.attempt += 1;
        self.state = .reconnecting;

        // Sleep then reconnect — written as synchronous code, std.Io handles async
        io.sleep(wait_ms * std.time.ns_per_ms) catch return;
        self.reconnect(io, config) catch |err| {
            std.log.warn("zbeam: reconnect to {s} failed: {}", .{ self.peer_name, err });
            self.onDisconnect(io, config);
        };
    }

    fn reconnect(self: *PeerConnection, io: std.Io, config: NodeConfig) !void {
        self.state = .handshaking;
        const addr = try EpmdClient.lookupNode(io, self.peer_name);
        const stream = try std.net.tcpConnectToAddress(io, addr);
        const result  = try HandshakeFsm.perform(
            stream, .initiating, config.node_name, config.cookie, DIST_FLAGS,
        );
        self.stream = stream;
        self.state  = .connected;
        self.attempt   = 0;
        self.backoff_ms = config.reconnect_backoff_min_ms;
        _ = result;
    }
};
```

### 8.3 Connection Pool

```zig
pub const ConnectionPool = struct {
    connections: std.StringHashMap(PeerConnection),
    mutex:       std.Thread.Mutex,

    // Get or create connection to peer. Creates if not exists.
    pub fn getOrConnect(
        self: *ConnectionPool,
        io:   std.Io,
        peer: []const u8,
        config: NodeConfig,
    ) !*PeerConnection {
        self.mutex.lock();
        defer self.mutex.unlock();
        const entry = try self.connections.getOrPut(peer);
        if (!entry.found_existing) {
            entry.value_ptr.* = PeerConnection{
                .peer_name  = peer,
                .state      = .idle,
                .stream     = null,
                .atom_cache = .{},
                .send_buf   = std.ArrayList(u8).init(self.allocator),
                .attempt    = 0,
                .backoff_ms = config.reconnect_backoff_min_ms,
            };
        }
        const conn = entry.value_ptr;
        if (conn.state != .connected) try conn.reconnect(io, config);
        return conn;
    }

    // Called when BEAM initiates connection to us (accepting role).
    pub fn accept(
        self: *ConnectionPool,
        io:   std.Io,
        stream: std.net.Stream,
        config: NodeConfig,
    ) !*PeerConnection {
        const result = try HandshakeFsm.perform(
            stream, .accepting, config.node_name, config.cookie, DIST_FLAGS,
        );
        self.mutex.lock();
        defer self.mutex.unlock();
        const entry = try self.connections.getOrPut(result.peer_name);
        entry.value_ptr.* = PeerConnection{
            .peer_name  = result.peer_name,
            .state      = .connected,
            .stream     = stream,
            .atom_cache = .{},
            .send_buf   = std.ArrayList(u8).init(self.allocator),
            .attempt    = 0,
            .backoff_ms = config.reconnect_backoff_min_ms,
        };
        return entry.value_ptr;
    }
};
```

### 8.4 Tick / Heartbeat Implementation

```zig
// Runs as a concurrent task per connection
fn tickLoop(io: std.Io, conn: *PeerConnection) !void {
    const TICK_INTERVAL_MS: u64 = 15_000;
    const TICK_TIMEOUT_MS:  u64 = 60_000;

    while (conn.state == .connected) {
        // Send tick (4 zero bytes)
        try conn.stream.?.write(io, &[_]u8{ 0, 0, 0, 0 });

        // Sleep for tick interval
        try io.sleep(TICK_INTERVAL_MS * std.time.ns_per_ms);
    }
}

// In the recv loop, track last received tick timestamp:
fn recvLoop(io: std.Io, conn: *PeerConnection) !void {
    var last_recv_ns = std.time.nanoTimestamp();
    while (true) {
        const length = conn.stream.?.read(io, &length_buf) catch |err| {
            conn.onDisconnect(io, config);
            return err;
        };
        last_recv_ns = std.time.nanoTimestamp();

        const elapsed_ms = (std.time.nanoTimestamp() - last_recv_ns) / std.time.ns_per_ms;
        if (elapsed_ms > 60_000) {
            std.log.warn("zbeam: peer {s} tick timeout", .{conn.peer_name});
            conn.onDisconnect(io, config);
            return error.TickTimeout;
        }
        // ... rest of recv processing
    }
}
```

---

## 9. Wire Protocol Compliance

### 9.1 Version Negotiation

zbeam MUST negotiate distribution protocol version as follows:

- Advertise `highest_version = 6`, `lowest_version = 5`
- If peer's `highest_version < 5`, MUST reject with log: "peer uses legacy protocol"
- If peer advertises `DFLAG_HANDSHAKE_23`, use OTP 23+ handshake format

### 9.2 Cookie Handling

Cookies MUST NOT be stored in plaintext in memory longer than required for digest computation. After digest is computed, zero the cookie buffer:

```zig
var cookie_buf: [256]u8 = undefined;
@memcpy(cookie_buf[0..cookie.len], cookie);
defer @memset(&cookie_buf, 0);
const digest = md5(cookie_buf[0..cookie.len], challenge);
```

### 9.3 Atom Cache Protocol

When `DFLAG_DIST_ATOM_CACHE` is negotiated, messages MUST include correct atom cache headers. zbeam MUST:

1. Track which atoms are already in the peer's cache (per connection).
2. Only send `ATOM_CACHE_REF` for atoms confirmed as cached.
3. Invalidate cache on reconnect.

### 9.4 Encoding Correctness

zbeam's ETF encoder MUST pass the following invariant:

```
∀ term T encoded by zbeam:
  BEAM's binary_to_term(zbeam_encode(T)) == T
```

This MUST be validated by the conformance test suite (§16).

```
∀ term T encoded by zbeam:
  BEAM's binary_to_term(zbeam_encode(T)) == T
```

This MUST be validated by the conformance test suite (§16).

---

## 10. Type System & Safety Guarantees

### 10.1 Phantom Types for PID Safety

PIDs MUST be wrapped in phantom types to prevent forgery:

```zig
pub fn RemotePid(comptime Node: type) type {
    return struct {
        inner: RawPid,
        // Node type parameter makes cross-node mistakes a compile error
    };
}

// This is a compile error — cannot send local PID as remote reference
const wrong: RemotePid(BeamNode) = local_actor.pid; // ERROR
```

### 10.2 Session Types for Protocol Channels

The handshake FSM MUST encode its state machine in the type system such that calling methods out of order is a compile error:

```zig
// Phase type progression — cannot call recvChallenge before sendName
pub const HandshakePhase = enum { idle, name_sent, status_received, connected };

pub fn HandshakeState(comptime phase: HandshakePhase) type {
    return struct {
        // Only available in correct phase
        pub const sendName = if (phase == .idle) sendNameImpl else @compileError("wrong phase");
        pub const recvChallenge = if (phase == .status_received) recvChallengeImpl else @compileError("wrong phase");
    };
}
```

### 10.3 Gradual ETF Decoding

Two-level strategy — see §5.3.2 (comptime typed) and §5.3.3 (dynamic `Term` union). The `Term` type is the runtime fallback. Section 5.3 is authoritative; this section documents the design intent:

- Known shapes → comptime `decode(T, reader)` — zero runtime dispatch
- Unknown shapes → `decodeDynamic(reader, arena)` → `Term` union

---

## 11. Error Model

All zbeam functions return error unions. No function panics under normal operation.

### 14.1 Error Categories

```zig
pub const EpmdError = error{
    ConnectionRefused,
    EpmdUnavailable,
    RegistrationFailed,
    NodeNotFound,
    InvalidConfig,
};

pub const HandshakeError = error{
    InvalidCookie,
    ProtocolVersionMismatch,
    UnexpectedMessage,
    ConnectionReset,
};

pub const DistError = error{
    InvalidFrame,
    UnknownControlTag,
    EtfDecodeError,
    ActorNotFound,
    MailboxFull,
    TickTimeout,
};

pub const EtfError = error{
    UnknownTag,
    TruncatedData,
    UnsupportedType,
    AtomTooLong,
    TypeMismatch,
    ArityMismatch,
    InvalidVersion,
};
```

### 14.2 Error Propagation to BEAM

When a zbeam actor exits with an error, it MUST:

1. Call `registry.unregisterPid(pid)`.
2. Send `EXIT` to all linked PIDs via dist — reason is the error atom.
3. Send `MONITOR_P_EXIT` to all monitors — reason is the error atom.

Error atom encoding (all fields snake_case):

```
error.OutOfMemory         →  atom 'out_of_memory'
error.InvalidCookie       →  atom 'invalid_cookie'
error.TypeMismatch        →  atom 'type_mismatch'
```

---

## 12. Memory Model

### 15.1 Allocator Architecture

zbeam uses a three-tier allocator model:

| Tier | Allocator | Scope | Purpose |
|---|---|---|---|
| Global | `std.heap.GeneralPurposeAllocator` | Process lifetime | Node tables, connection state |
| Per-connection | Arena, reset on disconnect | Connection lifetime | Recv buffers, fragment assembly |
| Per-message | Fixed-buffer from arena | Message handling | ETF decode scratch space |

### 15.2 Ownership Rules

1. Messages decoded from the network are owned by the **mailbox** until dequeued by the actor.
2. Once dequeued, the message is owned by the **actor's stack frame**.
3. Data passed to `Effects.Send` is **copied** into the outgoing ETF buffer — the actor retains ownership of the original.
4. `BinaryView` values are valid only within the current message-handling scope — see §5.3.4 for lifetime rules.

---



## 13. Concurrency Model

### 13.1 Foundation: std.Io as the Concurrency Abstraction

zbeam's entire concurrency model is built on `std.Io` (Zig 0.16). This is non-negotiable — there is no hand-rolled thread pool, no custom event loop, no custom fiber scheduler. `std.Io` is the pluggable execution backend.

**Key principle from Zig 0.16**: code is written as synchronous/blocking. The `Io` backend decides whether that blocking is real (threaded) or virtual (evented). This is what the core team calls "asynchrony without concurrency" — you get async I/O behavior without async function coloring.

```
zbeam code (synchronous style)
         │
         │  passed io: std.Io
         ▼
┌─────────────────────────────────────┐
│           std.Io Backend            │
├──────────────┬──────────────────────┤
│ Threaded     │ Evented (io_uring /  │
│ (OS threads) │ kqueue / epoll)      │
│              │                      │
│ Simpler,     │ High concurrency,    │
│ higher cost  │ lower overhead       │
└──────────────┴──────────────────────┘
```

### 13.2 Structural Concurrency via Io.Group

All concurrent tasks in zbeam — peer connections, actor fibers, the listener loop — MUST use `std.Io.Group`. There is no unstructured concurrency:

```
Main (io.Group: node_group)
  ├── EPMD registration task
  ├── Listener task (io.Group: connection_group per peer)
  │     ├── handlePeerConnection(peer_A)
  │     │     ├── distReceiveLoop
  │     │     └── distSendLoop
  │     └── handlePeerConnection(peer_B)
  │           └── ...
  └── Actor group (io.Group: actor_group)
        ├── actor_fiber(pid_1)
        ├── actor_fiber(pid_2)
        └── actor_fiber(pid_N)
```

Every group MUST have a `defer group.cancel(io)` — no fire-and-forget tasks.

### 13.3 Pluggable Backend Selection

zbeam exposes no opinion on which backend to use. The application chooses at startup:

```zig
// Option A: Threaded — simpler, better for CPU-bound work
var threaded_io = std.Io.Threaded.init(allocator);
defer threaded_io.deinit();
const node = try zbeam.start(threaded_io.io(), config);

// Option B: Evented — better for high-connection-count, I/O bound
// (availability depends on platform and Zig version)
var evented_io = std.Io.Evented.init(allocator);
defer evented_io.deinit();
const node = try zbeam.start(evented_io.io(), config);
```

This means a zbeam node can run as a high-throughput evented node or a simpler threaded node **without changing any zbeam or actor code**.

### 13.4 Task Lifecycle Rules

1. Every `io.async` future MUST be `defer future.cancel(io)` guarded.
2. Every `io.concurrent` task in a group is cancelled when the group goes out of scope via `defer group.cancel(io)`.
3. Actor tasks are cancelled (and EXIT signals sent) when the actor group is torn down.
4. zbeam MUST NOT call any blocking syscall directly — all blocking MUST go through the `io` parameter.

### 13.5 Synchronization via std.Io.Event

Cross-task synchronization (e.g., mailbox notification) uses `std.Io.Event` — NOT mutexes or condition variables for the hot path:

```zig
// Delivery (from dist receive task)
mailbox.event.set();

// Wait (from actor task) — suspends task, not thread
try mailbox.event.wait(io);
```

`std.Io.Event` integrates with the `Io` backend — with `Io.Evented`, this is zero-cost suspension; with `Io.Threaded`, it uses a futex.

---

## 14. Security Model

### 14.1 Cookie Authentication

Cookie-based authentication as specified in EDP MUST be implemented exactly. zbeam MUST NOT connect to a peer that fails the challenge-response verification.

### 14.2 TLS (Post-MVP)

TLS support via `std.crypto.tls` is defined as a post-MVP feature. The connection abstraction MUST be designed to accept a generic `Stream` type so TLS can be substituted without API changes:

```zig
pub fn connect(comptime Stream: type, stream: Stream, ...) !Connection(Stream);
```

### 14.3 Input Validation

All data received from the network MUST be validated before processing:

- ETF decode MUST reject terms with malformed length fields.
- Atom strings MUST be validated as valid UTF-8 (when `DFLAG_UTF8_ATOMS` is negotiated).
- Message sizes MUST be bounded (configurable, default 128 MiB) to prevent memory exhaustion.
- Fragment sequence IDs MUST be validated for monotonicity.

---

## 15. Integration Contracts

### 15.1 Node Naming Contract

A zbeam node MUST register with EPMD using the format `<name>@<host>` where:

- `<name>` matches `[a-zA-Z0-9_]+`
- `<host>` is a resolvable hostname or IP address
- The full name MUST be unique in the cluster

### 15.2 Elixir Integration

From an Elixir node's perspective, a zbeam node appears as a standard Erlang node. The following operations MUST work without any special configuration on the Elixir side:

```elixir
# Node discovery
Node.connect(:"zbeam@127.0.0.1")   # MUST return true
Node.list()                          # MUST include :"zbeam@127.0.0.1"

# Named process messaging
send({:my_zig_actor, :"zbeam@127.0.0.1"}, {:compute, data})

# RPC
:erpc.call(:"zbeam@127.0.0.1", :zig_module, :function, [args])

# Monitoring
ref = Process.monitor({:my_zig_actor, :"zbeam@127.0.0.1"})
# If actor exits: receive {:DOWN, ^ref, :process, _, reason}

# Linking
Process.link(remote_zig_pid)
# If actor exits abnormally: current process receives EXIT signal
```

### 15.3 Erlang Integration

```erlang
% All standard dist operations MUST work
net_kernel:connect_node('zbeam@127.0.0.1').          % → true
erlang:monitor(process, {my_zig_actor, 'zbeam@127.0.0.1'}).
gen_server:call({my_zig_actor, 'zbeam@127.0.0.1'}, Request).
rpc:call('zbeam@127.0.0.1', zig_module, fn_name, Args).
```

### 15.4 Gleam Integration

Gleam compiles to BEAM bytecode and uses Erlang distribution natively. No special handling required — any operation valid from Erlang is valid from Gleam.

### 15.5 zbeam-side Actor Contract

A zbeam actor that wishes to be callable as a `gen_server` from BEAM MUST implement the following message protocol:

```zig
// $gen_call — standard gen_server call protocol
// BEAM sends: {:"$gen_call", {from_pid, ref}, request_term}
// Actor MUST reply: {ref, reply_term} sent to from_pid

pub fn handleGenCall(
    actor: *Actor,
    from: Pid,
    ref: Ref,
    request: Term,
) !void {
    const reply = processRequest(request);
    try Effects.Send.call(actor.send_cap, from, .{ ref, reply });
}
```

---

## 16. Conformance Requirements

### 16.1 Test Suite Categories

A conforming zbeam implementation MUST pass all tests in these categories:

| Category | Tests | Tooling |
|---|---|---|
| **ETF Roundtrip** | Encode then decode every supported term type, compare with `binary_to_term/1` on a live BEAM node | Elixir test harness |
| **EPMD** | Register, lookup, names — on a real EPMD instance | `epmd -daemon` in CI |
| **Handshake** | Full handshake as initiator and acceptor — with a live OTP 25, 26, 27 node | OTP multi-version CI |
| **Message Passing** | Send/receive `{:ok, term}`, `{:error, atom}`, binary, large map | Elixir ExUnit |
| **Link Semantics** | Actor exits normally → no signal; exits with error → EXIT to linked process | Elixir ExUnit |
| **Monitor Semantics** | Monitor remote actor → DOWN on exit with correct reason | Elixir ExUnit |
| **Fragmentation** | Messages larger than 64KB are fragmented and reassembled correctly | Generated test data |
| **Atom Cache** | 2048 atom slots respected, cache invalidated on reconnect | Protocol-level inspection |
| **Reconnect** | Node disconnect and reconnect — existing monitors detect DOWN | Elixir ExUnit |

### 16.2 Interoperability Matrix

| OTP Version | Handshake v5 | Handshake v6 | DFLAG_HANDSHAKE_23 |
|---|---|---|---|
| OTP 23 | MUST | N/A | MUST |
| OTP 24 | MUST | MUST | MUST |
| OTP 25 | MUST | MUST | MUST |
| OTP 26 | SHOULD | MUST | MUST |
| OTP 27 | SHOULD | MUST | MUST |

### 16.3 Conformance Test Skeleton

The following examples are the minimum required test cases. CI MUST start a real EPMD (`epmd -daemon`) and a real BEAM node (`elixir --name test@127.0.0.1 --cookie test_cookie`) before running these tests.

**Test 1 — ETF Roundtrip (Elixir ExUnit)**:
```elixir
defmodule ZbeamEtfTest do
  use ExUnit.Case

  # zbeam encodes a term and sends it. Elixir receives and compares.
  test "integer roundtrip" do
    assert_receive {:from_zig, 42}, 1_000
  end

  test "atom roundtrip" do
    assert_receive {:from_zig, :hello}, 1_000
  end

  test "binary roundtrip" do
    assert_receive {:from_zig, <<"hello world">>}, 1_000
  end

  test "nested tuple roundtrip" do
    assert_receive {:from_zig, {:ok, {:nested, 1, 2.5}}}, 1_000
  end

  test "large binary (> 64KB triggers fragmentation)" do
    large = :binary.copy(<<"x">>, 131_072)  # 128KB
    assert_receive {:from_zig, ^large}, 5_000
  end
end
```

**Test 2 — Link Semantics (Elixir ExUnit)**:
```elixir
defmodule ZbeamLinkTest do
  use ExUnit.Case

  test "normal actor exit sends no EXIT signal" do
    pid = spawn_link(fn ->
      # link to zig actor that exits normally
      Node.connect(:"zbeam@127.0.0.1")
      zig_pid = :erpc.call(:"zbeam@127.0.0.1", :actors, :spawn_oneshot, [])
      Process.link(zig_pid)
      # zig actor will exit normally after 100ms
      Process.sleep(200)
    end)
    # If EXIT was sent, pid would crash and this test would fail
    assert Process.alive?(pid) == false  # exited normally, not crashed
  end

  test "abnormal actor exit propagates EXIT signal" do
    Process.flag(:trap_exit, true)
    zig_pid = :erpc.call(:"zbeam@127.0.0.1", :actors, :spawn_crashing, [])
    Process.link(zig_pid)
    assert_receive {:EXIT, ^zig_pid, :crash_reason}, 2_000
  end
end
```

**Test 3 — Monitor Semantics (Elixir ExUnit)**:
```elixir
defmodule ZbeamMonitorTest do
  use ExUnit.Case

  test "monitor receives DOWN when zig actor exits" do
    zig_pid = :erpc.call(:"zbeam@127.0.0.1", :actors, :spawn_oneshot, [])
    ref = Process.monitor(zig_pid)
    assert_receive {:DOWN, ^ref, :process, ^zig_pid, :normal}, 2_000
  end

  test "monitor receives DOWN with correct reason on crash" do
    zig_pid = :erpc.call(:"zbeam@127.0.0.1", :actors, :spawn_crashing, [])
    ref = Process.monitor(zig_pid)
    assert_receive {:DOWN, ^ref, :process, ^zig_pid, :crash_reason}, 2_000
  end
end
```

**Test 4 — Named Actor REG_SEND (Elixir ExUnit)**:
```elixir
defmodule ZbeamRegistryTest do
  use ExUnit.Case

  test "send to named zig actor by name" do
    Node.connect(:"zbeam@127.0.0.1")
    # zbeam node registers actor as :echo_server at startup
    send({:echo_server, :"zbeam@127.0.0.1"}, {:ping, self()})
    assert_receive {:pong, _from_pid}, 1_000
  end

  test "whereis unknown name returns nil on zbeam side" do
    result = :erpc.call(:"zbeam@127.0.0.1", :registry, :whereis, [:nonexistent])
    assert result == :undefined
  end
end
```

**Test 5 — Reconnect (Elixir ExUnit)**:
```elixir
defmodule ZbeamReconnectTest do
  use ExUnit.Case

  test "monitor detects DOWN after zbeam restart, UP after reconnect" do
    zig_pid = :erpc.call(:"zbeam@127.0.0.1", :actors, :spawn_long_lived, [])
    ref = Process.monitor(zig_pid)

    # Kill and restart the zbeam node externally (test helper)
    ZbeamHelper.kill_and_restart(:"zbeam@127.0.0.1")

    assert_receive {:DOWN, ^ref, :process, _, :noconnection}, 5_000

    # After restart, new connection should work
    ZbeamHelper.wait_connected(:"zbeam@127.0.0.1", 10_000)
    assert Node.ping(:"zbeam@127.0.0.1") == :pong
  end
end
```

---

## 17. Non-Goals & Explicit Exclusions

The following are **explicitly out of scope** for zbeam 0.1.0 and MUST NOT be implemented in the MVP:

1. **OTP behaviour implementations in Zig** — no `GenServer`, `Supervisor`, `GenStatem` in Zig. Use BEAM supervisors to supervise zbeam actors.
2. **Hot code reload** — shared libraries and Zig binaries cannot be hot-swapped like BEAM modules.
3. **Distributed Erlang security hardening** — TLS, mutual certificate auth, and node blocklisting are post-MVP.
4. **Scheduler modification (Level 4)** — zbeam does not modify OTP internals.
5. **Full OTP `rpc` module compatibility** — `rpc:call` works by convention (gen_server protocol), not by zbeam implementing the `rpc` module.
6. **Persistent term / ETS emulation** — zbeam actors have their own state; they do not emulate ETS.

---

## 18. Versioning Policy

zbeam follows Semantic Versioning 2.0.0:

- **MAJOR**: Breaking changes to the Actor API or ETF encoding behavior.
- **MINOR**: New capabilities (TLS, new dist flags, new effect types).
- **PATCH**: Bug fixes, conformance test additions, performance improvements.

The wire protocol version (EDP v5/v6) is **not** under zbeam's versioning — it follows OTP's versioning.

**Minimum Zig version: 0.16.0** — `std.Io`, `std.Io.Group`, `std.Io.Event`, and `io.async`/`io.concurrent` are first introduced in 0.16.0 and are non-negotiable dependencies of zbeam's architecture. There is no compatibility path for Zig < 0.16.0.

---

## 19. References

| # | Title | URL |
|---|---|---|
| [1] | Erlang Distribution Protocol | https://www.erlang.org/doc/apps/erts/erl_dist_protocol.html |
| [2] | External Term Format | https://www.erlang.org/doc/apps/erts/erl_ext_dist.html |
| [3] | EPMD Man Page (OTP 26) | https://www.erlang.org/docs/26/man/epmd |
| [4] | RFC 2119 — Key Words in RFCs | https://www.rfc-editor.org/rfc/rfc2119 |
| [5] | Zig 0.16.0 Language Reference | https://ziglang.org/documentation/0.16.0/ |
| [6] | Zig 0.16.0 Release Notes (std.Io) | https://ziglang.org/download/0.16.0/release-notes.html |
| [7] | std.Io usage discussion (ziggit) | https://ziggit.dev/t/a-little-help-with-io-please-i-am-trying-to-understand-how-to-use-the-new-io-interface-for-zig/14006 |
| [8] | Ergo Framework (Go reference impl) | https://github.com/ergo-services/proto |
| [9] | Multiparty Session Types — Fowler et al. | https://arxiv.org/pdf/1608.03321 |
| [10] | Safe Actor Programming with MPST (2026) | https://arxiv.org/abs/2602.24054 |
| [11] | Build Systems à la Carte — Mokhov et al. | https://dl.acm.org/doi/10.1145/3236774 |
| [12] | Koka: Effect Types — Leijen | https://koka-lang.github.io/koka/doc/index.html |
| [13] | SemVer 2.0.0 | https://semver.org |

---

*End of zbeam Technical Specification v0.2.0-draft*
