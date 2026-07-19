# Distribution handshake evidence

## Scope

OTP 23+ `N` name/challenge messages, status, challenge reply, acknowledgement, MD5 cookie digest, and initiating/accepting FSMs.

## Properties

- handshake packets enforce a bounded two-byte length;
- node names are non-empty and owned after decode;
- invalid state transitions fail;
- digest comparison uses timing-safe equality;
- socket I/O is isolated in the transport battery;
- protocol codec/FSM owns no socket.

## Verification

```sh
zig build test-unit
zig build test-integration
zig build test-all
```

A deterministic TCP harness completed initiating and accepting roles concurrently and verified peer identities. This does not establish OTP 25–27 compatibility; real target-version nodes remain required before checking the roadmap compatibility item.
