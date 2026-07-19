# Lab 01 — Mailbox Correctness

**Status:** Planned; blocked until the actor battery has a queue implementation.

## Objective

Define and verify a thread-safe, single-consumer mailbox contract under concurrent delivery.

## Hypothesis

A mutex-guarded queue with predicate checks under the lock and notification after enqueue preserves every message and avoids lost wakeups under a threaded `std.Io` backend.

## Experiment

- run 1, 2, 4, 8, and 16 producers against one consumer;
- tag messages with `{producer_id, sequence}`;
- vary queue capacity and shutdown timing;
- assert no loss, duplication, corruption, deadlock, or per-producer reordering;
- record contention and wakeup counts.

## Required evidence

Commands, Zig version, CPU/thread count, raw counters, failure seeds, and a Phase C stress record.

## Promotion gate

Mailbox code enters `src/zbeam/actor/` only after the contract and regression test are documented.
