# Lab 12 — Protocol Typestate

**Status:** Experimental; depends on a verified runtime handshake FSM.

## Objective

Compare a typed handshake API with a conventional runtime state machine.

## Hypothesis

Typestate can prevent invalid local transition calls, but untrusted wire input and reconnect behavior still require runtime validation.

## Experiment

Encode initiating and accepting handshake transitions, create compile-fail invalid transitions, and compare error reporting and API complexity with the runtime FSM.

## Required evidence

Transition table, compile-fail fixtures, wire-error tests, and maintenance-cost assessment.

## Promotion gate

The typed API must preserve protocol observability and cannot replace runtime validation.
