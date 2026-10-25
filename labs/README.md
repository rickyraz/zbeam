# Research Labs

Labs are isolated experiments for claims that are not ready for production modules. They produce evidence; they do not define the public API.

## Status

Eleven labs (01–04, 07–08, 10–12, 14–15) have runnable experiments; this does
not mean all eleven are production-verified or their full promotion gates have
passed. Labs 05, 06, 09 and 13 remain plans because the repo has no production
arena lifecycle, local ownership-transfer path, alternate transport backend or
general actor scheduler to study. Their ordering-dependent work stays deferred.

## Run

Use Zig 0.16.0 from the repository root:

```sh
timeout 240 zig build test-labs -j2 --summary all
zig build lab-01 -j2 --summary all
```

`test-labs` is opt-in and separate from `test-all`; `lab-NN` runs one available
experiment. Run with Zig 0.16.0, the repository's minimum tested build API; Zig
0.17 compatibility is not established by these commands. No production battery imports lab code. Results and scope limits
are in the [verification record](../docs/evidence/phase-c/2026-10-13-lab-contracts.md).

## Execution order

| Phase | Labs | Purpose |
|---|---|---|
| Runtime correctness | 01–05 | Mailbox, demand, backpressure, reconnect, and slot lifecycle |
| Ownership and transport | 06–10 | Local transfer, message representation, I/O, backend boundaries, and identity |
| Type and policy experiments | 11–15 | Typestate, protocol states, demand policy, fan-out, and sizing |

## Completion contract

A completed lab contains:

1. a falsifiable hypothesis;
2. runnable code or scripts;
3. environment and command records;
4. raw results;
5. a conclusion that records whether the hypothesis survived;
6. links to any production change justified by the evidence.

Lab code MUST remain outside `src/zbeam/` until its invariant and boundary are accepted through an ADR.
