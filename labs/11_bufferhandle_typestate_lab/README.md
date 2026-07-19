# Lab 11 — BufferHandle Typestate

**Status:** Experimental; never imported by production modules.

## Objective

Measure which borrowed/owned/forwarded states Zig types can enforce without a language-level borrow checker.

## Hypothesis

Separate types can reject unconditional forward-then-access patterns, while conditional runtime branches still require atomic runtime validation.

## Experiment

Implement minimal borrowed, owned, and forward-only APIs; add compile-fail cases for forbidden methods; document aliasing patterns that remain expressible.

## Required evidence

Compile-fail fixtures, runtime misuse tests, generated-code inspection, and a precise list of unenforced obligations.

## Promotion gate

Typestate enters production only if it removes real misuse without obscuring ownership or adding speculative generic machinery.
