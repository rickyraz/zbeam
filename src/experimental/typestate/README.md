# Typestate Experiments

This directory isolates compile-time API experiments from production modules.

Experiments MAY model handshake phases, borrowed/owned handles, or forward-only capabilities. They MUST include compile-fail misuse cases and MUST document obligations that remain runtime-only.

Production code under `src/zbeam/` cannot import this directory. Promotion requires:

1. a demonstrated misuse in a production-facing API;
2. a simpler runtime/API alternative comparison;
3. accepted ADR coverage;
4. unit and compile-fail tests;
5. no weakening of runtime validation for untrusted input.
