# Lab 03 — Observable Backpressure

**Status:** Planned; requires a working OTP peer and demand-gated receive path.

## Objective

Verify from outside zbeam that exhausted actor demand stops socket reads and bounds memory.

## Hypothesis

When effective demand reaches zero, the receive window eventually throttles the OTP sender while mailbox and process memory remain bounded.

## Experiment

Use a fast OTP sender and a deliberately slow zbeam actor. Record sender throughput, TCP receive-window behavior, mailbox depth, RSS, and recovery after new demand.

## Required evidence

Packet capture, load-generator source, metric timeline, kernel/OTP versions, and exact commands.

## Promotion gate

The project may claim transport-level backpressure only after this black-box oracle passes reproducibly.
