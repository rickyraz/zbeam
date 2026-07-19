# OTP interoperability matrix orchestration

## Scope

The external matrix runs the registered echo peer independently against OTP 25, 26, and 27. Each configured runtime must connect, send one registered message, receive the reply, and observe clean zbeam exit.

## Entry points

```sh
zig build test-interop
./scripts/interop/otp_matrix.sh
```

`OTP_ERL_25`, `OTP_ERL_26`, and `OTP_ERL_27` select runtime executables. Missing versions print `SKIP`; they are never counted as passes. GitHub Actions provisions each target version in an independent matrix job.

## Local result

OTP 25–27 were unavailable locally. OTP 28.4.1 produced development-only evidence:

```text
SKIP OTP 25
SKIP OTP 26
SKIP OTP 27
connect=true
reply={<0.10.0>,hello}
PASS development_otp28
```

The declared OTP 25–27 compatibility claim remains pending until the target CI jobs execute successfully.
