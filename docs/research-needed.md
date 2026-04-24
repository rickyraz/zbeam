## 1. Zero-copy actor-to-actor message passing

This is the most strategic research item.

The spec currently admits that when a `BufferHandle` is sent to another local actor, the safe path is still `toOwned()`, which means **copying**. The long-term vision is ownership transfer of an arena slot without copying. The main research questions are:

* can arena-slot ownership be transferred across actors without copying,
* is reference counting needed, or is an ownership flag enough,
* can Zig `comptime` be used to prevent a handle from being used after `promote()`,
* should `arena_id` be globally unique or only per connection. 

This matters because if it fails, the “zero-copy internal path” remains only a roadmap item and the design stays copy-based internally.

## 2. Full io_uring buffer ring integration

The spec already prepares `TransportArena` and the right alignment, but it explicitly says full buffer-ring integration is not exposed through Zig `std.Io` 0.16 yet. The research questions are:

* whether zbeam must drop down directly to `std.os.linux`,
* whether it is safe to combine low-level `io_uring` buffer registration with `std.Io.Group` lifecycle management,
* what the interaction with cancellation looks like,
* how fallback to normal `recv()` can remain transparent without breaking the abstraction boundary. 

This is important because it determines whether the claim of reducing the kernel→userspace copy can actually be realized.

## 3. Demand composition for multi-consumer / fan-out

The current demand signal is still simple: one actor declares capacity, and transport reads only when demand exists. But if one connection fans out to multiple consumers, the research questions become:

* how multiple actor demands should be composed,
* whether a demand combinator is needed,
* how to prevent one slow actor from damaging fairness for the others,
* whether this model can align naturally with GenStage/Broadway-style pull-based flow. 

This matters if zbeam wants to participate in more realistic streaming and pipeline workloads.

## 4. Compile-time enforcement for `BufferHandle` lifetime

The spec explicitly says `BufferHandle` lifetime is **documented**, but not actually enforced by the type system. The research questions are:

* whether phase types / type-state in Zig can mark a handle as valid only within a certain scope,
* whether crossing an async boundary without `toOwned()` can be detected at compile time,
* how far Zig `comptime` can simulate a linear or affine discipline. 

This is strongly PL-adjacent. If it works, it could become one of zbeam’s strongest differentiators.

## 5. Optimal values for `transport_buffer_count` and `transport_buffer_size`

The spec marks these as research-dependent because the optimal values depend on `io_uring` availability and traffic shape. The research questions are:

* how many slots are ideal per connection,
* when 64 KB is enough and when it is too small,
* how slot size interacts with Erlang distribution fragmentation,
* when `ArenaExhausted` appears and what the correct recovery policy should be. 

This looks operational, but it is actually important for latency, throughput, and bounded memory usage.

## 6. Demand deadlock / liveness failure

The spec even introduces a `DemandDeadlock` error, which means it already recognizes the system can stall if an actor never calls `grantOne()`. The research questions are:

* how to detect this liveness failure reliably,
* whether a watchdog or timeout is needed,
* whether actors should always receive initial demand > 0,
* how to distinguish a slow actor from a completely stalled one. 

This is important because demand-based flow control is strong for backpressure, but it can also freeze the system if the actor contract is wrong.

## 7. Mailbox thread safety beyond the “mutex fix”

Even though the spec says the mailbox data race is fixed, I still consider this an active research area, not a closed one. The remaining questions are:

* whether `event.wait()/reset()` is actually safe across all supported backends,
* whether lost-wakeup or contention patterns remain,
* whether mutex-guarded `LinearFifo` is sufficient or whether a different queue primitive is needed,
* how it behaves under high load and high thread counts. 

So the spec’s “fix” is a major step, but its correctness still needs to be proven empirically and semi-formally.

## 8. `TransportArena` slot recycling correctness

Because `BufferHandle` now carries `arena_id`, the research questions are:

* when a slot is actually safe to recycle,
* how to guarantee an actor is not still holding a handle to a slot that has already been reused,
* whether documentation rules are enough,
* whether each slot needs a generation counter. 

In my view this is highly important and should probably be promoted into an explicit design item.

## 9. Local send path without ETF re-encode

The spec says sending to a remote BEAM node still ETF-encodes into an outgoing buffer, while sending to a local zbeam actor should move toward `BufferHandle` transfer, and full zero-copy transfer remains a research goal. The research questions are:

* what the final internal message representation should be,
* what the “unit of transfer” for local messaging should be,
* whether the local protocol should remain `Term`, `BufferHandle`, or some hybrid,
* how to avoid copying without violating ownership rules. 

This is directly tied to intra-node performance.

## 10. Interaction between `std.Io` and low-level Linux paths

The spec explicitly asks whether it is acceptable to drop into `std.os.linux` for buffer-ring registration while all other I/O still goes through `std.Io`. The further questions are:

* whether cancellation semantics stay consistent,
* who owns descriptors and resource lifetimes,
* whether abstraction leakage will weaken the backend-agnostic design claim. 

This is not just an implementation detail; it touches the overall design philosophy.

## 11. Session types for lifetimes and protocol channels

The spec still keeps the ambition of session types / phase types, and its roadmap references point in that direction as well. The research questions are:

* whether Zig is ergonomic enough for this,
* which parts are worth making compile-time,
* which parts are better left runtime-checked,
* whether the safety gain is worth the API complexity. 

This will influence whether zbeam becomes “just a runtime” or a runtime with stronger type-driven design.

## 12. Conformance for actually observable backpressure

The spec adds new test categories:

* slow actor does not OOM,
* sender is throttled within 10 seconds,
* actor receives exactly N messages after granting N demand,
* buffer ring fallback correctness,
* mailbox has no race under threaded backend. 

That means research and testing are still needed to determine:

* whether demand really propagates TCP backpressure in observable reality,
* how long it takes before sender throttling is measurable,
* how to prove this is not just a design assumption.

## 13. Reconnect semantics and demand reset

The spec says that on reconnect, `DemandSignal` must be reset to `initial_actor_demand`, and actors must grant again when ready. The research questions are:

* whether this reset is sufficient,
* what happens to in-flight partial frames,
* whether a mailbox that still contains old state needs special handling,
* what happens to actors that are blocked in `receive()`. 

This matters for correctness under real network churn.

## 14. Arena namespace and connection identity

Because `arena_id` is used to identify buffer slots, the research questions are:

* whether a per-connection local `arena_id` is sufficient,
* what happens if future transfer crosses actors and connections,
* whether a stronger namespace or composite key like `{conn_id, slot_id}` is needed. 

This looks small, but it can become foundational for internal zero-copy transfer.

## 15. Whether demand-based design should become the primary actor-runtime model

v0.3.0 already shifts primary control from mailbox depth to demand-based flow control. The research questions are:

* whether all actors fit a “grant after processing finishes” model,
* how actors that need batching or prefetch should behave,
* whether per-message demand is enough, or whether `grant(n)` is needed,
* how demand interacts with scheduler fairness. 

This could evolve into a major runtime-design research area on its own.

---

## Most compact summary

If you compress all of this down, the `research needed` items in v0.3.0 fall into 5 major blocks:

1. **Zero-copy ownership model**
   `BufferHandle`, `promote()`, slot transfer, lifetime enforcement. 

2. **Kernel / transport integration**
   `io_uring`, buffer rings, fallback path, cancellation semantics. 

3. **Demand-driven runtime semantics**
   backpressure, multi-consumer composition, demand deadlock, reconnect reset. 

4. **Concurrency correctness**
   mailbox synchronization, slot recycling, event semantics, threaded-backend proof. 

5. **PL-adjacent enforcement**
   type-state / session-style lifetime and protocol guarantees. 

I can also turn this into a **research priority table** next: what blocks the MVP, what blocks v1, and what can be deferred into longer-term R&D.
