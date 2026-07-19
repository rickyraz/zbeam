# OTP Interoperability Tests

**Status:** Planned for milestone M1.

This suite will start real OTP nodes and verify behavior visible across the distribution boundary. It is verification infrastructure, not a consumable `zbeam-interop` package.

Initial matrix:

- OTP 25, 26, and 27;
- initiating and accepting handshakes;
- registered send and reply;
- link, monitor, disconnect, and reconnect behavior.

Tests must record OTP versions, isolate Erlang cookies, use bounded timeouts, and preserve relevant wire fixtures under `fixtures/`.
