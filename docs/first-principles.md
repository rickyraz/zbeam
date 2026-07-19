# First-principles implementation guide

This document explains why the initial implementation uses its current types, boundaries, and protocol steps. The authoritative wire values remain the primary sources in [`protocol-sources.md`](protocol-sources.md).

## Bytes and integer widths

A wire protocol is a byte agreement between independent machines. Zig integer widths mirror fields defined by Erlang/OTP; they are not chosen from host CPU preference.

| Zig type | Wire size | Current use | Why |
|---|---:|---|---|
| `u8` | 1 octet / 8 bits | ETF tags, EPMD tags, pass-through marker | These fields identify one of at most 256 byte values. One octet is the protocol unit. |
| `u16` | 2 octets / 16 bits | EPMD and handshake lengths, atom/name lengths | Those protocols define two-byte lengths, with a theoretical maximum of 65,535. Lower policy limits still apply. |
| `u32` | 4 octets / 32 bits | Distribution frame length, challenge, creation, PID fields | OTP assigns four octets to these fields. Distribution messages need more range than handshake frames. |
| `u64` | 8 octets / 64 bits | OTP 23+ capability flags | Each capability occupies one bit. Flags above bit 31 require the upper half. |
| `[16]u8` | 16 octets / 128 bits | Cookie digest | MD5 output is exactly 128 bits; a fixed array makes the required size impossible to omit. |

One octet is eight bits because the protocol and modern byte-addressed networking define it that way. For example, decoding bytes `0x12 0x34` as big-endian `u16` means `(0x12 << 8) | 0x34 = 0x1234`: shifting eight creates room for exactly one following octet.

Multibyte protocol integers are written in big-endian network order. Explicit shifts make the result independent of host endianness.

## ETF: tags before values

ETF is self-describing: a one-byte tag says how the following bytes must be interpreted. Decoding therefore follows three steps:

1. verify the ETF version byte (`131`, hexadecimal `0x83`);
2. read one tag and its protocol-defined length/value fields;
3. reject truncation, unsupported tags, invalid UTF-8, excessive depth, and excessive allocation before constructing an owned term.

`decodePrefix` exists because a distribution packet concatenates a control ETF term and an optional payload ETF term. `decode` builds on it and rejects trailing data when a caller expects exactly one term.

Decoded atoms, binaries, collections, and PID node names are copied. The receive buffer belongs to transport and may be recycled; actor-visible terms must not silently borrow that lifetime.

## EPMD: registration is a connection lifetime

EPMD maps a short node name to a TCP distribution port. Registration is not a permanent database write: EPMD keeps the name alive while the registration TCP connection remains open. Therefore `Registration` owns the stream and `close` means unregister.

Lookup uses another short-lived connection. Variable lengths are read and bounded before allocation because every network length is untrusted, even when EPMD normally runs on loopback.

## Handshake: prove ordering and shared secret knowledge

The handshake has two independent concerns:

- a finite-state machine proves messages occur in the legal order;
- challenge/response digests prove both sides know the cookie without sending the cookie itself.

The legacy OTP proof is `MD5(cookie ++ decimal(challenge))`. MD5 is retained solely for Erlang distribution compatibility. Constant-time digest comparison avoids leaking the first mismatching byte through ordinary early-exit timing.

The initiator and acceptor FSMs reject skipped, repeated, or reordered events. A connection becomes usable only after reciprocal proof succeeds.

## Distribution: route before decoding payload

A distribution frame is `[u32 length][body]`. Length zero is a tick. The current body starts with the one-byte pass-through marker and then contains a control ETF term plus an optional payload ETF term.

Control is decoded first because it answers where the message goes. Payload remains borrowed wire bytes until routing selects the local actor. This prevents unrelated messages from forcing allocations or failing on payload tags the selected actor never needs.

## Mailbox and demand

A mailbox must be bounded or it can hide backpressure by turning a slow actor into unbounded memory growth. `std.Io.Queue` supplies thread-safe bounded storage; caller-provided storage makes capacity explicit.

Many producers may deliver, but one logical actor token may receive. The mailbox atomically changes owner from reserved ID zero to the first valid actor ID and rejects different tokens afterward.

Demand is a separate atomic credit counter. One credit means permission for one message. Compare/exchange loops prevent concurrent updates from losing increments, and checked addition prevents integer wraparound. Transport demand gating is still pending; the primitive alone does not prove TCP backpressure.

## Runtime boundaries

The registry owns names and identity mappings. Callers own mailbox storage, and scheduling remains separate. Named delivery resolves a mailbox while holding the registry lock, then releases the lock before a potentially blocking queue operation. Otherwise one full mailbox could freeze all registry activity.

Transport parses bytes and owns sockets. Actor code handles behavior. Runtime code composes them. Keeping these responsibilities separate prevents actor business logic from controlling buffer or connection lifetime.

## Benchmark boundary

The Port baseline echoes a fixed 32-byte payload with four-byte packet framing. The distribution path echoes the same payload through EPMD, authentication, routing, and ETF control framing. The result is an initial end-to-end comparison, not an algorithmic equivalence or performance claim.
