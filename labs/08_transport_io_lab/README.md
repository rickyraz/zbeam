# Lab 08 — Transport I/O Paths

**Status:** Runnable portable framing experiment; backend performance comparisons remain open.

## Objective

Characterize blocking/threaded `std.Io`, preallocated buffers, and future registered-buffer paths.

## Hypothesis

A correct preallocated portable path captures most allocation benefits; io_uring is justified only if measured copy or syscall costs remain material.

## Experiment

Trace bytes from socket to decoder, measure copies/syscalls/allocations, exercise cancellation and short reads, and compare supported backends on identical traffic.

## Required evidence

Kernel and Zig versions, syscall traces, benchmark data, cancellation cleanup records, and fallback behavior.

## Runnable subset

Run `zig build lab-08 -j2 --summary all`. The [experiment](experiment.zig)
varies maximum reader chunks from 1 to 11 bytes. Each case must reconstruct the
same seven-byte frame, allocate it once, free it once and leave a following tick
unread. Oversized headers must fail before allocation; injected OOM must stop
before payload consumption.

The byte path is `counted source -> stack header -> owned packet`. The output
reports reader calls and allocator counters, not socket syscalls or total decoder
copies. No preallocated alternative, cancellation backend comparison, io_uring,
syscall trace or performance win is established by this matrix.

## Promotion gate

Linux-specific code remains behind the transport boundary and cannot become the default without leak-free cancellation evidence.
