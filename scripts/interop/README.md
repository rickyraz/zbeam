# OTP interoperability scripts

Build zbeam, then run the available local OTP matrix:

```sh
zig build
OTP_ERL_25=/opt/otp25/bin/erl \
OTP_ERL_26=/opt/otp26/bin/erl \
OTP_ERL_27=/opt/otp27/bin/erl \
./scripts/interop/otp_matrix.sh
```

Missing target versions are reported as `SKIP`, never `PASS`. If no target executable is configured, the script uses the current `erl` only as explicitly labelled development evidence.
