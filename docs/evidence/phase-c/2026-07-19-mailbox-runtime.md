# Mailbox and runtime evidence

## Scope

Bounded mailbox, logical single-consumer enforcement, atomic demand credits, named actor registration, delivery, and termination.

## Design choices

- `std.Io.Queue` provides bounded MPMC storage and cancellation-aware blocking;
- zbeam adds a logical owner token to narrow consumption to one actor;
- full queues block producers rather than allocate unbounded memory;
- runtime registry locking uses `std.Io.Mutex`;
- task scheduling remains separate and unimplemented.

## Stress workload

Eight concurrent producers each delivered 1,000 `{producer, sequence}` messages through a 64-slot mailbox to one consumer.

## Assertions

- all 8,000 messages received;
- no duplicate or dropped sequence;
- each producer's sequence remained ordered;
- second logical consumer rejected;
- registry name removed and mailbox closed on termination.

## Verification

```sh
zig build test-unit
zig build test-stress
zig build test-all
```
