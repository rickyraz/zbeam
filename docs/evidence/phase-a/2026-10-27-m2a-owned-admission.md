# M2a internal owned-admission ledger

`runtime/task_admission.zig` is an internal, externally locked ledger, not a
public task runtime. Each actor reserves four logical queue positions and five
outstanding tickets. A ticket retains inline completion space until collection
or explicit post-join discard. Input is copied with one allocator provenance;
failed insertion rolls back without transfer. Claim/finish/take distinguish
queue ownership, consumer ownership, payload destruction and ticket release.

Linux x86-64 WSL2, Zig 0.17.0, PR #7 base `4c8e563`:

- Focused ledger tests: 3/3 in debug and safe, including caller-buffer mutation,
  rejected-copy rollback, OOM restoration, 1 MiB limit and five live 1 MiB copies.
- Full core/labs in each mode: 63/63 steps, 55/55 newly executed tests;
  unaffected runs cached. Raw summaries retained adjacent to this record.
- Completing all five requests frees every payload but still rejects admission
  until results are collected, without any allocation attempt on `WouldBlock`.
  The counted allocator balances exact allocated/freed bytes after cleanup.
- Formatting/whitespace checked; imports preserve the battery DAG. No exported
  task API, runtime scheduling, transport, protocol or flags are changed.

The eventual runtime must serialize all ledger operations with its lifecycle
mutex, enqueue transactionally, and join consumers before draining/discarding.
These local tests do not establish that future concurrent integration. Rollback
removes this internal module and its test import; existing public APIs remain.
