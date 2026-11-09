Code.require_file("two_worker_owner.ex", __DIR__)
[bin] = System.argv()
true = Node.alive?()
peer = String.to_atom("custom_example_#{System.pid()}@127.0.0.1")
options = [name: :custom_pair, peer: peer, executable: Path.expand(bin), profile: :custom]

{:ok, supervisor} =
  Supervisor.start_link([{TwoWorkerOwner, options}],
    strategy: :one_for_one,
    max_restarts: 3,
    max_seconds: 5
  )

try do
  {:ok, "HELLO"} = TwoWorkerOwner.call(:custom_pair, :a, "hello")
  {:ok, "WORLD"} = TwoWorkerOwner.call(:custom_pair, :b, "world")
  IO.puts("PASS compiled Zig uppercase handler on both workers")
after
  Supervisor.stop(supervisor)
end
