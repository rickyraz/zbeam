Code.require_file("research_support.exs", __DIR__)
Code.require_file("../examples/native_worker_owner.ex", __DIR__)
[bin] = System.argv()
parent = self()
launch = fn ->
  context = ResearchPeer.start(bin, 500)
  send(parent, {:launched, self()})
  context
end
{:ok, owner} = NativeWorkerOwner.start_link(name: :owner_contract, launch: launch, timeout_ms: 1500)
try do
  receive do {:launched, ^owner} -> :ok after 5000 -> raise "startup timeout" end
  caller = Task.async(fn -> GenServer.call(owner, {:hash, "first"}) end)
  true = Enum.any?(1..100, fn _ -> if :sys.get_state(owner).pending, do: true, else: (Process.sleep(1); false) end)
  {:error, :busy_or_invalid} = GenServer.call(owner, {:hash, "overlap"})
  {:ok, digest} = Task.await(caller)
  true = digest == :crypto.hash(:sha256, "first")
  {:error, :busy_or_invalid} = GenServer.call(owner, {:hash, :not_binary})
  {:error, :busy_or_invalid} = GenServer.call(owner, {:hash, :binary.copy(<<0>>, 1_048_577)})
  {:ok, digest} = GenServer.call(owner, {:hash, "second"})
  true = digest == :crypto.hash(:sha256, "second")
after
  GenServer.stop(owner)
end
Process.flag(:trap_exit, true)
{:ok, owner} = NativeWorkerOwner.start_link(name: :timeout_contract, launch: launch, timeout_ms: 50)
receive do {:launched, ^owner} -> :ok after 5000 -> raise "startup timeout" end
state = :sys.get_state(owner)
ref = Process.monitor(owner)
{:error, :timeout} = GenServer.call(owner, {:hash, "late"})
receive do {:DOWN, ^ref, :process, ^owner, {:shutdown, :timeout}} -> :ok after 1000 -> raise "owner did not exit" end
nil = Port.info(state.port)
IO.puts("PASS single-flight rejection, payload bounds, ordered results and late-reply teardown")
