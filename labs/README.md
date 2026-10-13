# Research Labs

Labs are isolated experiments for claims that are not ready for production modules. They produce evidence; they do not define the public API.

## Status

Labs 01–02 have executable contract experiments. Other directories remain
plans or experiment contracts, not completed research. A passing subset does not
close a lab's broader promotion gate.

## Run

Use Zig 0.16.0 from the repository root:

```sh
timeout 240 zig build test-labs -j2 --summary all
zig build lab-01 -j2 --summary all
```

`test-labs` is opt-in and separate from `test-all`; `lab-NN` runs one available
experiment. No production battery imports lab code. Results and scope limits
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
