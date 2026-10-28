# Connection error policy separation — 2026-10-28

The initial `serve-workers` integration inadvertently made concurrency and
internal-invariant errors fatal for the existing M1 sequential service too. The
node now preserves M1's prior connection-boundary policy and applies the new
fatal classification only to M2b. Exhausted request IDs and unexpected active
reservations also fail the M2b service instead of repeatedly accepting peers
that cannot make progress. Malformed peer input remains a connection failure.

Zig 0.17.0 Linux/WSL: debug/safe `zig build test-all test-labs
 test-task-lifecycle test-worker-recovery -j2 --summary all` each passed 73/73
steps, 125/127 newly executed Zig tests with two conditional skips; other steps
were cached. The new table-driven test checks each affected error for both
profiles and the existing one-connection, cancellation and OOM policy. M1 and
M2 recovery campaigns and external spin watchdog passed in both modes. This
classification test does not simulate exhausting 2^64 IDs.

Rollback the node policy and its test together; restoring the initial expression
reintroduces the M1 policy regression. This does not change the wire schema.
