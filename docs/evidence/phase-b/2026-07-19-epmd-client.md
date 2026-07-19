# EPMD client evidence

## Scope

Pure ALIVE2/PORT_PLEASE2 codecs and `std.Io` TCP client registration/lookup.

## Properties

- request length prefix validated by unit tests;
- ALIVE2 short and extended creation responses supported;
- registration failure and missing-node responses are errors;
- node name and extra-field lengths checked before allocation;
- registration socket ownership remains with an explicit `Registration` handle.

## Verification

```sh
epmd -daemon
zig build test-unit
zig build test-integration
zig build test-all
```

The integration test registered a unique node on local OTP 28 EPMD, looked it up while the registration socket remained open, and verified the advertised port and node name. OTP 25–27 remain pending in the compatibility matrix.
