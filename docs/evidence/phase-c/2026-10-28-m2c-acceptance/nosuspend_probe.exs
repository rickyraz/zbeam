root = Path.expand("../../../..", __DIR__)
Code.require_file(Path.join(root, "examples/two_worker_owner.ex"))
Code.require_file(Path.join(root, "tests/interop/m2c_test_support.exs"))
ExUnit.start()
[bin] = System.argv()
peer = String.to_atom("m2c_probe_#{System.pid()}@127.0.0.1")
opts = [name: :m2c_probe, peer: peer, executable: bin, timeout_ms: 5_000]
{:ok, supervisor} = Supervisor.start_link([{TwoWorkerOwner, opts}], strategy: :one_for_one)

try do
  owner = Process.whereis(:m2c_probe)
  {_, native} = M2cTestSupport.child_pids(:sys.get_state(owner).port)
  1 = :erlang.trace(owner, true, [:call, {:tracer, self()}])
  1 = :erlang.trace_pattern({:erlang, :send, 3}, [{:_, [], [{:return_trace}]}], [:local])
  {_, 0} = System.cmd("kill", ["-STOP", to_string(native)])
  payload = :binary.copy(<<23>>, 1_048_576)

  tasks =
    for actor <- [:a, :b] do
      Task.async(fn -> TwoWorkerOwner.hash(:m2c_probe, actor, payload) end)
    end

  collect = fn collect, results ->
    receive do
      {:trace, ^owner, :return_from, {:erlang, :send, 3}, value} ->
        collect.(collect, [value | results])

      {:trace, ^owner, :call, {:erlang, :send, _}} ->
        collect.(collect, results)
    after
      1_500 -> IO.inspect(Enum.reverse(results), label: "send returns")
    end
  end

  collect.(collect, [])
  IO.inspect(Enum.map(tasks, &Task.yield(&1, 100)), label: "outcomes")
after
  if Process.alive?(supervisor), do: Supervisor.stop(supervisor)
end
