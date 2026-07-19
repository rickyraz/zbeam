# Protocol wire vectors

These deterministic vectors exercise the documented OTP 23+ `N` handshake layout and four-byte distribution framing. They are structural vectors transcribed from the protocol field definitions linked in `docs/protocol-sources.md`; they are not captures and do not establish OTP compatibility by themselves.

`manifest.zig` keeps bytes reviewable beside conformance assertions. Real-node behavior is verified separately by `scripts/interop/otp_matrix.sh`.
