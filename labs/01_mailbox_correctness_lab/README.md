# Lab 01 — Mailbox Correctness

**Status:** Runnable production-contract experiment; broader shutdown/fault injection remains open.

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

## Runnable subset

Run `zig build lab-01 -j2 --summary all` from the repository root. The
[experiment](experiment.zig) exercises the existing actor battery with 1/2/4/8/16
producers, 128 messages each, and capacities 1/4/64. Every received sequence is
checked, producers are joined before storage destruction, and close/drain is
checked separately. Output records all 15 cases (11,904 total deliveries).

This measures correctness, not throughput or contention. An external timeout
bounds a broken test; no test run establishes freedom from all thread schedules.
Wakeup counters, blocked-operation shutdown races and sanitizer runs remain open.

## Promotion gate

The mailbox already exists in `src/zbeam/actor/`. This lab adds verification,
not a new mailbox implementation or a stronger task-identity guarantee.
