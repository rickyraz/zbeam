# Research Labs

Labs are isolated experiments for claims that are not ready for production modules. They produce evidence; they do not define the public API.

## Status

All labs are currently **planned**. A directory containing only documentation does not indicate completed research.

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
