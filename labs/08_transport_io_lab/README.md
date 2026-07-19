# Lab 08 — Transport I/O Paths

**Status:** Planned; portable TCP path precedes io_uring research.

## Objective

Characterize blocking/threaded `std.Io`, preallocated buffers, and future registered-buffer paths.

## Hypothesis

A correct preallocated portable path captures most allocation benefits; io_uring is justified only if measured copy or syscall costs remain material.

## Experiment

Trace bytes from socket to decoder, measure copies/syscalls/allocations, exercise cancellation and short reads, and compare supported backends on identical traffic.

## Required evidence

Kernel and Zig versions, syscall traces, benchmark data, cancellation cleanup records, and fallback behavior.

## Promotion gate

Linux-specific code remains behind the transport boundary and cannot become the default without leak-free cancellation evidence.
