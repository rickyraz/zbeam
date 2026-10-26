# Lab 11 — BufferHandle Typestate

**Status:** Runnable compile-failure and alias counterexamples; never imported by production modules.

## Objective

Measure which borrowed/owned/forwarded states Zig types can enforce without a language-level borrow checker.

## Hypothesis

Separate types can reject unconditional forward-then-access patterns, while conditional runtime branches still require atomic runtime validation.

## Experiment

Implement minimal borrowed, owned, and forward-only APIs; add compile-fail cases for forbidden methods; document aliasing patterns that remain expressible.

## Required evidence

Compile-fail fixtures, runtime misuse tests, generated-code inspection, and a precise list of unenforced obligations.

## Runnable subset

Run `zig build lab-11 -j2 --summary all`. This runs the
[experiment](experiment.zig) and requires [direct access](compile_fail.zig) to
fail compilation with the expected missing-method diagnostic. An unrelated
compiler error is not accepted as success.

| Attempt | Result required by the experiment |
|---|---|
| `ForwardOnly.access()` | Compile failure |
| `ForwardOnly.inner.access()` | Compiles and reads bytes |
| Access through a prior borrowed slice | Still possible |
| Forward twice on one modeled owner | Runtime error |
| Copy owner before forwarding each value | Both calls succeed |

The sequential consumed flag is a counterexample model, not synchronization or
ownership transfer. All borrowed storage stays alive throughout each test.
Removing a method narrows convenience APIs but does not enforce linearity,
field privacy or borrow invalidation. The broad safety hypothesis is therefore
not established. Generated-code inspection, concurrent access and a safe shared
ownership identity remain open; no `BufferHandle` is introduced.

## Promotion gate

Typestate enters production only if it removes real misuse without obscuring ownership or adding speculative generic machinery.
