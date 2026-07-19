# Minimum real distribution peer evidence

## Scope

EPMD registration, accepting handshake, four-byte pass-through framing, `REG_SEND` routing to `echo`, and `SEND` reply to the remote PID.

## Environment

- Zig 0.16.0
- Erlang/OTP 28.4.1
- loopback TCP with local EPMD

OTP 28 is development evidence outside the declared OTP 25–27 target matrix.

## Commands

```sh
epmd -daemon
zig build
./zig-out/bin/zbeam echo zbeam_echo cookie

erl -noshell -name client@127.0.0.1 -setcookie cookie -eval \
"N='zbeam_echo@127.0.0.1',
 io:format('connect=~p~n',[net_kernel:connect_node(N)]),
 {echo,N}!{self(),hello},
 receive M -> io:format('reply=~p~n',[M]) after 3000 -> halt(2) end,
 halt()."
```

## Observed result

```text
connect=true
reply={<0.10.0>,hello}
```

The peer ignored unrelated registered messages without decoding their unsupported payloads, then routed the `echo` message and exited cleanly after one reply.
