---
title: Bounded ETF Decoding
tags:
  - zbeam
  - etf
  - security
  - learning
---

# Bounded ETF Decoding

ETF is untrusted when it arrives from a BEAM node over the network. A decoder must not let a peer choose how much memory or stack zbeam consumes.

> [!note] Scope
> This note describes the current ETF decoder in `src/zbeam/etf/codec.zig`. It does not claim OTP interoperability; `docs/implementation-status.md` remains the implementation-status authority.

## The receive path

```text
BEAM node
  -> TCP distribution frame
  -> transport checks the four-byte frame length
  -> ETF decoder reads version, tag, and declared length
  -> decoder validates the value against configured limits
  -> decoder verifies that encoded bytes are available
  -> decoder allocates owned Zig storage when the term needs it
  -> runtime handles the decoded term
```

The transport boundary already limits a distribution frame before allocating it in `src/zbeam/transport/distribution_io.zig`. ETF repeats value-specific checks because one bounded packet can contain a maliciously sized ETF binary, tuple, or list declaration.

## Example: `BINARY_EXT`

An ETF binary contains a tag, a four-byte big-endian length, and exactly that many bytes.

```text
131 | 109 | 00 00 00 05 | 68 65 6c 6c 6f
 ^     ^        ^              ^
 |     |        |              "hello"
 |     |        declared length = 5
 |     BINARY_EXT
 ETF version
```

For this term, the safe order is:

```zig
const length = try cursor.readU32();
if (length > limits.max_binary_bytes) return error.LimitExceeded;
const source = try cursor.take(length);
const owned = try allocator.dupe(u8, source);
```

`length` is supplied by the peer. `cursor.take(length)` proves that the packet actually contains the declared number of bytes before `allocator.dupe` allocates and copies them.

## Why the checks exist

Without bounds, a small hostile packet can declare a huge binary or collection length. Trusting that number can cause excessive allocation, `OutOfMemory`, or deep recursive decoding.

Current limits in `Limits` are:

| Limit | Default | Protects |
|---|---:|---|
| `max_binary_bytes` | 16 MiB | one binary allocation |
| `max_atom_bytes` | 255 bytes | atom allocation and UTF-8 validation |
| `max_collection_len` | 1,048,576 | tuple/list item allocation |
| `max_depth` | 64 | nested tuple/list/PID recursion |

The decoder rejects an over-limit value with `error.LimitExceeded`, truncated data with `error.Truncated`, and invalid UTF-8 atom bytes with `error.InvalidAtom`.

## Is the two-step check the best mechanism?

**Validate a semantic limit, then verify available bytes before allocation** is the right baseline for a length-prefixed leaf value such as `BINARY_EXT` or a UTF-8 atom. It is simple, auditable, avoids an unnecessary pre-scan, and follows the essential mitigation for attacker-controlled allocation lengths.

It is not sufficient by itself for every ETF term. A complete bounded decoder needs four protections:

1. **Transport frame limit**: reject an oversized network frame before allocating the frame buffer.
2. **Semantic value limit**: reject a declared binary length, atom length, collection arity, or nesting depth above the configured `Limits`.
3. **Physical and structural preflight**: prove the encoded bytes required at this point exist before allocating from a peer-declared count when possible.
4. **Fallible allocation and ownership cleanup**: propagate allocator failure and release partially decoded children on failure.

The combined receive path has all four protections for atom and binary values. The ETF decoder applies the same cheap lower-bound preflight to tuples and lists before allocating their `Term` arrays, then retains depth checks, fallible allocation, and partial-initialization cleanup for the full recursive decode.

> [!note] Collection distinction
> For a tuple with `N` children, each child needs at least one tag byte. For a proper list, the `N` children plus the `NIL_EXT` tail need at least `N + 1` bytes. The decoder checks that lower bound against remaining input before allocating. It does not replace full recursive decoding, because each tag can require more bytes.

## Trade-offs

| Approach | Benefit | Cost | Decision |
|---|---|---|---|
| Trust declared length and allocate | Smallest code | Memory-exhaustion vulnerability | Never use for network ETF |
| Limit check, then allocate | Caps maximum allocation | A truncated collection can still allocate up to its cap | Minimum acceptable baseline |
| Limit check, available-byte check, then allocate | Rejects truncated leaf values before allocation | One bounds check | Use for binary and atom values |
| Full pre-scan, then decode | Can prove complete structural validity before allocations | Duplicates parser complexity and CPU; difficult ownership/error paths | Avoid by default |
| Streaming/lazy terms | Can reduce peak memory for large data | Lifetime and actor-boundary complexity | Add only after measurement proves need |
| Lower collection-size preflight | Rejects obviously impossible tuple/list arity before allocation | A small amount of term-specific code | Recommended improvement for collection decoding |

A full pre-scan is usually not the best default. It parses every term twice or needs a separate validator that can drift from the decoder. The better minimal design is **single-pass decoding with explicit limits and cheap local preflights**.

## Practical rule for new ETF tags

Before allocating from any field encoded by a peer:

```text
read declared length
-> validate semantic maximum
-> validate arithmetic used for capacity
-> verify available bytes when the term has a fixed or known lower-bound size
-> allocate fallibly
-> decode with depth and collection limits
```

For a variable-size nested term, validate the maximum before allocation and retain cleanup with `errdefer`. Do not invent a second parser unless profiling or a security review demonstrates that a local preflight is insufficient.

## Where to read and test

- Decoder: `src/zbeam/etf/codec.zig`
- Owned term representation: `src/zbeam/etf/term.zig`
- Frame-size boundary: `src/zbeam/transport/distribution_io.zig`
- Current unit checks: the `test` blocks at the end of `src/zbeam/etf/codec.zig`
- ETF fixtures: `fixtures/etf/manifest.tsv`

Run the relevant checks:

```sh
zig build test-unit
zig build test-conformance
```

## References

- [Erlang/OTP 27 External Term Format](https://www.erlang.org/docs/27/apps/erts/erl_ext_dist.html)
- [MITRE CWE-789: Memory Allocation with Excessive Size Value](https://cwe.mitre.org/data/definitions/789.html)
- [Project protocol source matrix](../docs/protocol-sources.md)
