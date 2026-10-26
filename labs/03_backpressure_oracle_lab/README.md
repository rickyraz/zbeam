# Lab 03 — Observable Backpressure

**Status:** Runnable white-box read/allocation oracle; full OTP measurement remains open.

## Objective

Verify from outside zbeam that exhausted actor demand stops socket reads and bounds memory.

## Hypothesis

When effective demand reaches zero, the receive window eventually throttles the OTP sender while mailbox and process memory remain bounded.

## Experiment

Use a fast OTP sender and a deliberately slow zbeam actor. Record sender throughput, TCP receive-window behavior, mailbox depth, RSS, and recovery after new demand.

## Required evidence

Packet capture, load-generator source, metric timeline, kernel/OTP versions, and exact commands.

## Runnable subset

Run `zig build lab-03 -j2 --summary all`. The [experiment](experiment.zig) uses
an unbuffered counted reader and an allocator that fails on its first allocation.
One hundred zero-demand attempts must perform no reads and never call that
allocator. A grant consumes exactly one frame, leaving the next tick unread;
a buffered reader is rejected before spending credit.

This is a deterministic trust-boundary oracle, not an OTP sender, kernel-window
or RSS experiment. Existing TCP pause/resume coverage remains in
[`tests/stress/backpressure_stress.zig`](../../tests/stress/backpressure_stress.zig),
run by `zig build test-stress`. The broader hypothesis still needs the stated
black-box metrics; these reader counters are not syscall counts.

## Promotion gate

The project may claim transport-level backpressure only after this black-box oracle passes reproducibly.
