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

On Linux with Zig, Python 3, Elixir and EPMD installed, build and run the example:

```sh
zig build -Doptimize=safe
sh scripts/interop/ensure_epmd.sh
elixir --erl '+S 2:2' --name pair_client@127.0.0.1 \
  --cookie development_cookie examples/supervised_two_workers.exs ./zig-out/bin/zbeam
```

The example starts one supervised native process, checks simultaneous exact
hashes on `a` and `b`, and stops `a` while `b` remains usable. It creates one
peer-name atom per VM and reuses it on restart. Applications may instead load `examples/two_worker_owner.ex` and
provide a fixed peer atom, an exclusive name and an executable path:

```elixir
Code.require_file("examples/two_worker_owner.ex")
opts = [name: :pair, peer: :"native_pair@127.0.0.1", executable: "./zig-out/bin/zbeam"]
{:ok, supervisor} = Supervisor.start_link([{TwoWorkerOwner, opts}], strategy: :one_for_one)
{:ok, digest} = TwoWorkerOwner.hash(:pair, :a, "abc")
:ok = TwoWorkerOwner.stop(:pair, :a)
{:ok, sibling_digest} = TwoWorkerOwner.hash(:pair, :b, "still running")
Supervisor.stop(supervisor)
```

The owner starts its own child; do not start another service using that name.
Only one call per actor is admitted before the owner mailbox; excess calls return
`{:error, :busy}`. Input is limited to 1 MiB. A timeout, caller death or loss of
connection/process can fail **both** pending calls and restart the child. A
distribution send returning `:nosuspend` did not send that request: its caller
receives `{:error, :busy}`, its admission slot is released, and an already-sent
sibling remains pending. A `:noconnect` result still fails the owner closed.
No request is retried automatically; work with uncertain outcome is never replayed.
The owner requires exclusive control of its peer connection and assumes trusted
local processes. `stop(owner, actor)` uses the same admission ticket as `hash`:
it returns `busy` instead of interrupting an in-flight call. A successful stop
joins and retires that actor without stopping its sibling; further calls to the
retired actor return `unavailable` until the native process is replaced. A
caller death or timeout after a stop was sent has an uncertain outcome and fails
the owner closed, without replay. The [M2c acceptance record](evidence/phase-c/2026-10-28-m2c-acceptance.md)
and [stop regression](evidence/phase-c/2026-11-05-owner-stop.md) cover this
restricted development example, not production certification.

## Compiled-handler composition (experimental)

A Zig embedding may set `node.Config.custom_handler` for the `workers` service.
This selects a separate profile using `{FromPid, Ref, {call, Binary}}` and
`{Ref, {ok, Binary}}`; it rejects `hash`. The ordinary `serve-workers` command
continues to use SHA-256 and rejects `call`. The handler borrows its runtime-owned
input during the call and returns 0–32 bytes in zeroed inline output storage;
see the [local handler contract](task-runtime.md#compiled-stateless-handler-local-only).
Discovery, bounded admission, stop, monitors and joined connection epochs are
shared with the two-worker service. The SHA-256 Elixir owner is not a
custom-call client.

The separate example executable compiles the Zig function in
[`examples/custom_worker.zig`](../examples/custom_worker.zig); replace that
function and rebuild to use another handler. Its example function uppercases
ASCII bytes and deliberately returns `handler_failed` for inputs above 32
bytes, retiring that actor. The runtime's general input limit remains 1 MiB.

```sh
zig build example-custom-worker -Doptimize=safe
sh scripts/interop/ensure_epmd.sh
elixir --erl '+S 2:2' --name custom_client@127.0.0.1 \
  --cookie development_cookie examples/custom_client.exs ./zig-out/bin/zbeam-custom-worker
```

The example launches its own guarded child, calls both actors, and cleans up the
connection and child. The [live interoperability campaign](evidence/phase-c/2026-11-05-handler-interop.md)
covers OTP 25/26/27 in both modes and Elixir fault scenarios, including
[actual-master CI](evidence/phase-c/2026-11-05-handler-interop.md#actual-merged-master-follow-up).
Production acceptance remains separate. The raw example is not the bounded
SHA-256 owner API and does not bound arbitrary BEAM senders.

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
A panic or corruption affects the whole native process, not just one worker. A
[test-only compiled-handler panic](evidence/phase-c/2026-11-05-handler-panic.md)
observes both actor monitors disconnect while the BEAM VM remains responsive; it
does not establish safety under memory corruption or OS-OOM.

Cookies appear in process arguments; there is no TLS. Authentication trusts the
peer node, not individual BEAM processes. External supervision and no-replay
recovery are deployment responsibilities. The Linux
[process-loss campaign](evidence/phase-c/2026-10-28-m2b-process-recovery.md)
covers the wire profile separately from the Elixir owner above. Do not expose
this profile to untrusted networks. [Acceptance evidence](evidence/phase-c/2026-10-28-m2b-acceptance.md)
and [implementation status](implementation-status.md) distinguish the supported
subset from remaining deployment and compatibility risks.
