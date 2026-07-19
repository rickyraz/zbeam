# Relationship to General-Purpose Async Runtimes

zbeam overlaps with asynchronous runtimes only at the implementation-problem level. Future runtime work includes:

- task scheduling and lifecycle management;
- structured concurrency through `std.Io.Group`;
- demand-driven backpressure;
- mailbox synchronization.

The project scope remains an Erlang distribution peer, not a general-purpose Zig equivalent of Tokio. None of these runtime capabilities is currently implemented.
