Code.require_file("research_support.exs", __DIR__)
Code.require_file("../examples/native_worker_owner.ex", __DIR__)
[bin, mode, count_arg] = System.argv()
true = mode in ["kill", "port_kill", "panic", "oom", "spin", "epmd"]
count = String.to_integer(count_arg)
true = count in 1..100
parent = self()
vm_pid = System.pid()
probe = spawn_link(fn ->
  loop = fn loop -> receive do {caller, ref} -> send(caller, ref); loop.(loop) end end
  loop.(loop)
end)
try do
  for trial <- 1..count do
    launches = :atomics.new(1, [])
    epmd_port = String.to_integer(System.get_env("ERL_EPMD_PORT", "4369"))
    launch = fn ->
      first = :atomics.add_get(launches, 1, 1) == 1
      fault = if first and mode in ["panic", "oom", "spin"], do: mode, else: "none"
      context = if mode == "port_kill" do
        port = Port.open({:spawn_executable, String.to_charlist(Path.join(Path.dirname(bin), "zbeam-port-echo"))},
          [:binary, {:packet, 4}, :exit_status, args: ["sha256"]])
        {port, nil}
      else
        ResearchPeer.start(bin, if(first, do: 200, else: 0), fault, epmd_port)
      end
      send(parent, {:launched, self(), context})
      context
    end
    {:ok, supervisor} = Supervisor.start_link([{NativeWorkerOwner, [name: :research_worker, launch: launch, timeout_ms: 1000]}],
      strategy: :one_for_one, max_restarts: 3, max_seconds: 5)
    try do
      {owner, {port, _peer}} = receive do {:launched, owner, context} -> {owner, context} after 5000 -> raise "no first worker" end
      {:os_pid, native_pid} = Port.info(port, :os_pid)
      if mode in ["kill", "port_kill"], do: {_, 0} = System.cmd("kill", ["-STOP", to_string(native_pid)])
      started = System.monotonic_time(:microsecond)
      caller = Task.async(fn -> GenServer.call(:research_worker, {:hash, "uncertain"}, 5000) end)
      # Ensure the owner has admitted the request before injecting external failure.
      true = Enum.any?(1..100, fn _ ->
        if :sys.get_state(owner).pending != nil, do: true, else: (Process.sleep(1); false)
      end)
      if mode in ["kill", "port_kill"], do: {_, 0} = System.cmd("kill", ["-KILL", to_string(native_pid)])
      if mode == "epmd", do: IO.puts("DROP_PRIVATE_EPMD")
      result = Task.await(caller, 6000)
      true = result in [{:error, :worker_lost}, {:error, :timeout}]
      failed = System.monotonic_time(:microsecond)
      {new_owner, _} = receive do {:launched, pid, context} -> {pid, context} after 5000 -> raise "no restart" end
      true = owner != new_owner
      input = "after_restart_#{trial}"
      {:ok, digest} = GenServer.call(:research_worker, {:hash, input}, 5000)
      true = digest == :crypto.hash(:sha256, input)
      ping = make_ref()
      send(probe, {self(), ping})
      receive do ^ping -> :ok after 500 -> raise "unrelated process failed" end
      true = vm_pid == System.pid()
      IO.puts("RESULT " <> JSON.encode!(%{mode: mode, trial: trial, request_outcome: inspect(result),
        request_to_failure_us: failed - started, request_to_first_good_reply_us: System.monotonic_time(:microsecond) - started,
        recovery_us: System.monotonic_time(:microsecond) - failed, launches: :atomics.get(launches, 1), beam_bytes: :erlang.memory(:total)}))
    after
      Supervisor.stop(supervisor)
    end
  end
  IO.puts("PASS explicit failure, supervised restart, unchanged VM and unrelated process")
after
  Process.unlink(probe)
  Process.exit(probe, :kill)
end
