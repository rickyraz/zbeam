Code.require_file("two_worker_owner.ex", __DIR__)
[bin] = System.argv()
true = Node.alive?()
peer = String.to_atom("pair_example_#{System.pid()}@127.0.0.1")
options = [name: :pair, peer: peer, executable: Path.expand(bin)]

{:ok, supervisor} =
  Supervisor.start_link([{TwoWorkerOwner, options}],
    strategy: :one_for_one,
    max_restarts: 3,
    max_seconds: 5
  )

try do
  inputs = [a: "hello a", b: "hello b"]

  tasks =
    for {actor, input} <- inputs do
      {input, Task.async(fn -> TwoWorkerOwner.hash(:pair, actor, input) end)}
    end

  for {input, task} <- tasks do
    expected = :crypto.hash(:sha256, input)
    {:ok, ^expected} = Task.await(task, 5_000)
    IO.puts("verified SHA-256: " <> input)
  end

  IO.puts("PASS supervised two-worker example")
after
  Supervisor.stop(supervisor)
end
