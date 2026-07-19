# Research and Risk Backlog

This backlog defines contributor work that requires evidence before entering the production design. The v0.5 specification remains an unimplemented target; [`implementation-status.md`](implementation-status.md) is authoritative for code status.

## Priority labels

- **P0 — MVP blocker:** required for one real OTP-compatible actor.
- **P1 — correctness blocker:** required before performance work or public compatibility claims.
- **P2 — optimization research:** considered only after the portable implementation is correct and measured.

## P0 — Minimum distribution peer

### Protocol source audit

**Required work**

- map ETF, EPMD, handshake, framing, control-message, heartbeat, and fragmentation requirements to primary Erlang/OTP documentation;
- identify OTP-version differences for OTP 25, 26, and 27;
- convert verified wire examples into repository fixtures.

**Acceptance evidence**

- citations to primary sources;
- byte-level fixtures with expected decoding;
- no undocumented protocol assumptions in implementation code.

### One-actor interoperability

**Required work**

- register one node through EPMD;
- complete initiating and accepting handshakes;
- expose one registered actor;
- exchange one documented message in each direction with real OTP nodes.

**Acceptance evidence**

- black-box tests against OTP 25, 26, and 27;
- packet captures or hexdumps matched to protocol fields;
- Phase B verification records.

### Port baseline

**Required work**

Compare one zbeam actor with one Erlang Port using the same workload and payload.

**Acceptance evidence**

- reproducible scripts;
- p50, p95, p99, throughput, memory, restart time, and BEAM scheduler impact;
- raw results, including negative results.

## P1 — Runtime correctness

### Mailbox contract

Define and test the mailbox as a thread-safe, single-consumer concurrent object. Required coverage includes concurrent delivery, shutdown, wakeup sequencing, ordering guarantees, and ownership enforcement.

### Demand liveness

Specify the distinction between valid zero demand and a stalled actor. Required coverage includes omitted grants, actor failure before grant, prolonged processing, diagnostics, and recovery policy.

### Observable backpressure

Demonstrate that zero effective demand stops transport reads, bounds memory, and throttles the remote sender. Design reasoning alone is insufficient.

### Reconnect and incarnation state

Define which fragment, atom-cache, demand, mailbox, and handle state is reset or retained after reconnect. Tests must interrupt active and fragmented traffic.

### Fragment and allocation bounds

Enforce message-size, fragment-count, partial-assembly, atom, and allocation limits before accepting untrusted input.

### Actor failure blast radius

Measure controlled errors, panics, and deliberate memory corruption separately. The process boundary protects the BEAM VM but does not establish isolation between actors sharing one zbeam process.

## P1 — Ownership correctness

### Arena slot identity and recycling

Determine whether slot identity requires `{connection, slot, generation}`. Prove that no slot is reused while any handle remains live and that stale handles are detected.

### Handle lifecycle

Define borrowed, owned, promoted, forwarded, and dropped states. Required tests cover concurrent promotion, access after promotion, double drop, missing drop diagnostics, and cancellation paths.

### Local message representation

Choose the internal representation only after comparing copied terms, decoded terms, and arena-backed payloads. “No ETF re-encode” must not be reported as “zero-copy” unless byte ownership also transfers without copying.

### Mailbox and arena ownership boundary

Transport owns buffers and actor code owns behavior. No raw slice or pointer may cross actor or asynchronous boundaries without an explicit ownership strategy.

## P2 — Deferred optimization research

### Copy threshold and buffer sizing

Benchmark message-size distributions before selecting `zero_copy_threshold`, buffer count, or buffer size defaults. Defaults require workload evidence rather than analogy alone.

### io_uring registered buffers

Document descriptor ownership, kernel-buffer lifecycle, cancellation, ring exhaustion, and fallback behavior. The portable `std.Io` path remains the required default until leak-free cancellation is demonstrated.

### Fan-out demand composition

Define broadcast and partition semantics, fairness, slow-consumer behavior, and effective-demand calculation. Zero-copy broadcast remains out of scope unless independent ownership can be proven.

### Per-scheduler arena partitioning

Measure contention on the shared arena before introducing scheduler-local partitions. No partitioning abstraction should be added without a demonstrated bottleneck.

### Static lifecycle enforcement

Evaluate typestate, forward-only APIs, and session-type experiments as optional safety improvements. Runtime validation remains mandatory for untrusted protocol input and runtime-dependent branches.

## Contributor completion rule

A backlog item is complete only when the repository contains implementation code, the smallest regression test that protects the invariant, and verification evidence under `docs/evidence/`. A specification edit by itself does not complete an item.
