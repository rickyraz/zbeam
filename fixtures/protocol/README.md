# Protocol wire vectors

These deterministic vectors exercise the documented OTP 23+ `N` handshake layout and four-byte distribution framing. They are structural vectors transcribed from the protocol field definitions linked in `docs/protocol-sources.md`; they are not captures and do not establish OTP compatibility by themselves.

`manifest.zig` keeps bytes reviewable beside conformance assertions. `m2b.tsv`
contains independently OTP-generated two-worker frames. `m3.tsv` contains
`call` request and binary reply frames for empty and 32-byte values, generated
by `scripts/interop/m3_fixtures.escript`; pinned OTP 25/26/27 outputs are
byte-identical. These vectors do not by themselves enable a custom service.
Real-node behavior is verified separately by `scripts/interop/otp_matrix.sh`.
