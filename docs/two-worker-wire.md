# Two fixed workers over Erlang Distribution

`serve-workers` provides two service-owned SHA-256 actors, named `a` and `b`,
through the separate `zbeam_workers` endpoint. It binds IPv4 loopback and serves
one authenticated peer at a time. `serve-worker` and its M1 contract are unchanged.
This is a development profile, not production certification.

## Run

```sh
zig build -Doptimize=safe
sh scripts/interop/ensure_epmd.sh
./zig-out/bin/zbeam serve-workers native_pair development_cookie
```

In another terminal, use an OTP node with the same cookie:

```sh
erl +S 2:2 -noshell -name pair_client@127.0.0.1 -setcookie development_cookie -eval '
  N = list_to_atom("native_pair@127.0.0.1"),
  true = net_kernel:connect_node(N),
  Call = fun(To, Cmd) ->
    Ref = make_ref(), To ! {self(), Ref, Cmd},
    receive {Ref, Reply} -> Reply after 5000 -> error(timeout) end
  end,
  {ok, A} = Call({zbeam_workers, N}, {discover, a}),
  {ok, B} = Call({zbeam_workers, N}, {discover, b}),
  true = (A =/= B),
  {ok, Digest} = Call(A, {hash, <<"abc">>}),
  Digest = crypto:hash(sha256, <<"abc">>),
  Monitor = erlang:monitor(process, A),
  ok = Call(A, stop),
  Down = list_to_atom("DOWN"),
  receive {Down, Monitor, process, A, normal} -> ok after 5000 -> error(no_down) end,
  {ok, B} = Call({zbeam_workers, N}, {discover, b}),
  halt().'
```

## Supervised Elixir owner

From an Elixir node using the same cookie, load `examples/two_worker_owner.ex`:

```elixir
Code.require_file("examples/two_worker_owner.ex")
{:ok, supervisor} = Supervisor.start_link([{TwoWorkerOwner, [name: :pair, peer: :"native_pair@127.0.0.1", executable: "./zig-out/bin/zbeam"]}], strategy: :one_for_one)
{:ok, digest} = TwoWorkerOwner.hash(:pair, :a, "abc")
Supervisor.stop(supervisor)
```

The owner starts its own native child; do not start another service with that
name. Its M2c failure campaign is still in progress.

## Contract and limits

Discovery replies `{Ref,{ok,Pid}}` or `{Ref,{error,noproc}}`. Hash accepts a
binary up to 1 MiB and replies `{Ref,{ok,Digest}}`; accepted work can instead
report `stopped`, `canceled` or `handler_failed`. Stop retires and joins that
one worker; its sibling and discovery endpoint remain live. Unknown/stale PID
sends are dropped. PID and named monitors share 64 slots per connection. The
full contract and ordering are in [ADR 0005](adr/0005-two-worker-wire-profile.md).

A single stream conservatively reserves capacity for **both** running workers
before every read, including ticks and controls. Saturation can therefore block
unrelated work and heartbeats. Replies have separate bounded credits; slow writes
or disconnects can drop replies. Accepted work is drained and discarded before
reconnect; it is never replayed. Stop/join and deadlines are cooperative, not
CPU preemption; a noncooperative task requires external process kill and reap.
A panic or corruption affects the whole native process, not just one worker.

Cookies appear in process arguments; there is no TLS. Authentication trusts the
peer node, not individual BEAM processes. External supervision and no-replay
recovery are deployment responsibilities. The Linux
[process-loss campaign](evidence/phase-c/2026-10-28-m2b-process-recovery.md)
provides a bounded test example, not a reusable supervisor. Do not expose this
profile to untrusted networks. [Acceptance evidence](evidence/phase-c/2026-10-28-m2b-acceptance.md)
and [implementation status](implementation-status.md) distinguish the supported
subset from remaining deployment and compatibility risks.
