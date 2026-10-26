Code.require_file("../../examples/native_worker_owner.ex", __DIR__)

ExUnit.start(
  trace: true,
  exclude: if(System.get_env("ONLY_EPMD"), do: [:ordinary], else: [:epmd])
)

defmodule WorkerRecoveryTest do
  use ExUnit.Case, async: false
  @root Path.expand("../..", __DIR__)
  @name :m1_test_owner

  defp await(predicate, timeout \\ 4_000) do
    deadline = System.monotonic_time(:millisecond) + timeout

    loop = fn loop ->
      if predicate.() do
        :ok
      else
        assert System.monotonic_time(:millisecond) < deadline, "bounded wait expired"
        Process.sleep(10)
        loop.(loop)
      end
    end

    loop.(loop)
  end

  defp live?(pid) do
    case File.read("/proc/#{pid}/stat") do
      {:ok, stat} -> not String.match?(stat, ~r/\) Z /)
      _ -> false
    end
  end

  defp close_port(port) do
    Port.close(port)
  rescue
    error in ArgumentError ->
      if Port.info(port) != nil, do: reraise(error, __STACKTRACE__)
  end

  defp kill(pid, signal) do
    {_, 0} = System.cmd("kill", ["-#{signal}", to_string(pid)], stderr_to_stdout: true)
  end

  defp next_worker do
    receive do
      {:launched, owner, port, peer} ->
        state = :sys.get_state(owner, 4_000)
        assert state.peer == peer
        {:os_pid, guard} = Port.info(port, :os_pid)

        [native] =
          File.read!("/proc/#{guard}/task/#{guard}/children")
          |> String.split()
          |> Enum.map(&String.to_integer/1)

        Process.put(:owned, [{guard, native} | Process.get(:owned, [])])
        {owner, state, guard, native}
    after
      5_000 -> flunk("no ready replacement")
    end
  end

  defp with_worker(mode, run) do
    Process.flag(:trap_exit, true)
    Process.put(:owned, [])
    parent = self()
    counter = :atomics.new(1, [])
    [bin, fault_bin] = System.argv()

    launch = fn ->
      first = :atomics.add_get(counter, 1, 1) == 1
      name = "m1_#{System.pid()}_#{System.unique_integer([:positive])}"
      cookie = Atom.to_string(Node.get_cookie())

      args =
        if (first or mode == :always_panic) and mode != :normal do
          [
            fault_bin,
            name,
            cookie,
            if(mode == :always_panic, do: "panic", else: Atom.to_string(mode)),
            System.get_env("ERL_EPMD_PORT", "4369")
          ]
        else
          [bin, "serve-worker", name, cookie]
        end

      # Private-EPMD trials keep both launches on the fixture's injected port.
      args =
        if System.get_env("ONLY_EPMD"),
          do: [
            fault_bin,
            name,
            cookie,
            if(first, do: "pause", else: "none"),
            System.fetch_env!("ERL_EPMD_PORT")
          ],
          else: args

      port =
        Port.open(
          {:spawn_executable, System.find_executable("python3")},
          [
            :binary,
            :exit_status,
            :stderr_to_stdout,
            args: [@root <> "/examples/worker_guard.py" | args]
          ]
        )

      peer = String.to_atom(name <> "@127.0.0.1")
      send(parent, {:launched, self(), port, peer})
      {port, peer}
    end

    {:ok, supervisor} =
      Supervisor.start_link([{NativeWorkerOwner, [name: @name, launch: launch, timeout_ms: 500]}],
        strategy: :one_for_one,
        max_restarts: 3,
        max_seconds: 5
      )

    Process.put(:supervisor, supervisor)
    vm = System.pid()

    probe =
      spawn(fn ->
        receive do
          {from, ref} -> send(from, ref)
        end
      end)

    try do
      run.(next_worker())
      assert System.pid() == vm
      ping = make_ref()
      send(probe, {self(), ping})
      assert_receive ^ping, 500
    after
      Process.exit(probe, :kill)
      if Process.alive?(supervisor), do: Supervisor.stop(supervisor)

      for {guard, native} <- Process.get(:owned, []) do
        await(fn -> not live?(native) and not live?(guard) end)
      end
    end
  end

  defp recovered(old_pid) do
    {_, state, _, _} = next_worker()
    assert state.pid != old_pid
    assert NativeWorkerOwner.hash(@name, "new work") == {:ok, :crypto.hash(:sha256, "new work")}
    state
  end

  @tag :ordinary
  test "port cleanup tolerates closure but preserves invalid arguments" do
    for close <- [
          &close_port/1,
          fn port ->
            NativeWorkerOwner.terminate(:normal, %{peer: :"cleanup_missing@127.0.0.1", port: port})
          end
        ] do
      port = Port.open({:spawn_executable, System.find_executable("cat")}, [:binary])
      assert Port.info(port) != nil
      close.(port)
      assert Port.info(port) == nil
      assert_raise ArgumentError, fn -> Port.close(port) end
      close.(port)
      assert_raise ArgumentError, fn -> close.(42) end
    end
  end

  @tag :ordinary
  test "correlated native work, caller admission, SIGKILL and stale replies" do
    with_worker(:normal, fn {owner, state, _, native} ->
      assert NativeWorkerOwner.hash(@name, "abc") == {:ok, :crypto.hash(:sha256, "abc")}
      assert NativeWorkerOwner.hash(@name, 42) == {:error, :invalid_input}

      assert NativeWorkerOwner.hash(@name, :binary.copy(<<0>>, 1_048_577)) ==
               {:error, :invalid_input}

      kill(native, "STOP")
      task = Task.async(fn -> NativeWorkerOwner.hash(@name, "uncertain") end)
      await(fn -> :sys.get_state(owner).pending != nil end)
      {_, _, old_ref, _, _} = :sys.get_state(owner).pending
      assert NativeWorkerOwner.hash(@name, "no queue") == {:error, :busy}
      send(owner, {make_ref(), {:ok, <<0::256>>}})
      assert elem(:sys.get_state(owner).pending, 2) == old_ref
      kill(native, "KILL")
      assert Task.await(task, 2_000) == {:error, :worker_lost}
      new = recovered(state.pid)
      {_, new_native} = hd(Process.get(:owned))
      new_owner = Process.whereis(@name)
      kill(new_native, "STOP")
      fresh = Task.async(fn -> NativeWorkerOwner.hash(@name, "not replayed") end)
      await(fn -> :sys.get_state(new_owner).pending != nil end)
      new_ref = elem(:sys.get_state(new_owner).pending, 2)
      send(new_owner, {old_ref, {:ok, <<0::256>>}})
      assert elem(:sys.get_state(new_owner).pending, 2) == new_ref
      kill(new_native, "CONT")
      assert Task.await(fresh, 2_000) == {:ok, :crypto.hash(:sha256, "not replayed")}
      assert new.pid != state.pid
    end)
  end

  @tag :ordinary
  test "normal process DOWN restarts the external process" do
    with_worker(:normal, fn {_, state, _, _} ->
      ref = make_ref()
      send(state.pid, {self(), ref, :stop})
      assert_receive {^ref, :ok}, 2_000
      recovered(state.pid)
    end)
  end

  for mode <- [:panic, :oom, :spin] do
    @tag :ordinary
    test "test-only #{mode} fails uncertain work without replay" do
      for _ <- 1..2 do
        with_worker(unquote(mode), fn {_, state, _, _} ->
          result = NativeWorkerOwner.hash(@name, "uncertain")
          assert result in [{:error, :worker_lost}, {:error, :timeout}]
          if unquote(mode) == :spin, do: assert(result == {:error, :timeout})
          recovered(state.pid)
        end)
      end
    end
  end

  @tag :ordinary
  test "connection loss tears down a suspended native process" do
    with_worker(:normal, fn {owner, state, _, native} ->
      kill(native, "STOP")
      task = Task.async(fn -> NativeWorkerOwner.hash(@name, "uncertain") end)
      await(fn -> :sys.get_state(owner).pending != nil end)
      assert Node.disconnect(state.peer)
      assert Task.await(task, 2_000) == {:error, :worker_lost}
      recovered(state.pid)
    end)
  end

  @tag :ordinary
  test "owner kill bypasses terminate but guardian still cleans up" do
    with_worker(:normal, fn {owner, state, _, native} ->
      Process.exit(owner, :kill)
      recovered(state.pid)
      await(fn -> not live?(native) end)
    end)
  end

  @tag :ordinary
  test "guardian SIGKILL also terminates its native child" do
    with_worker(:normal, fn {_, state, guard, native} ->
      kill(guard, "KILL")
      recovered(state.pid)
      await(fn -> not live?(native) end)
    end)
  end

  @tag :ordinary
  test "failed readiness closes the launcher even without a terminate callback" do
    Process.flag(:trap_exit, true)
    [bin, _] = System.argv()
    parent = self()

    launch = fn ->
      name = "startup_#{System.pid()}_#{System.unique_integer([:positive])}"

      port =
        Port.open(
          {:spawn_executable, System.find_executable("python3")},
          [
            :binary,
            :exit_status,
            :stderr_to_stdout,
            args: [
              @root <> "/examples/worker_guard.py",
              bin,
              "serve-worker",
              name,
              Atom.to_string(Node.get_cookie())
            ]
          ]
        )

      {:os_pid, guard} = Port.info(port, :os_pid)
      child_path = "/proc/#{guard}/task/#{guard}/children"
      await(fn -> File.exists?(child_path) and String.trim(File.read!(child_path)) != "" end)
      [native] = File.read!(child_path) |> String.split() |> Enum.map(&String.to_integer/1)
      send(parent, {:failed_start, guard, native})
      {port, String.to_atom("missing_" <> name <> "@127.0.0.1")}
    end

    assert {:error, :not_ready} =
             NativeWorkerOwner.start_link(
               name: :startup_owner,
               launch: launch,
               restart_delay_ms: 0
             )

    assert_receive {:failed_start, guard, native}
    await(fn -> not live?(guard) and not live?(native) end)
    assert NativeWorkerOwner.hash(:startup_owner, "not ready") == {:error, :not_ready}
  end

  @tag :ordinary
  test "restart intensity stops a permanently unhealthy child" do
    with_worker(:always_panic, fn _ ->
      supervisor = Process.get(:supervisor)

      for i <- 1..4 do
        assert NativeWorkerOwner.hash(@name, "fault") in [
                 {:error, :worker_lost},
                 {:error, :timeout}
               ]

        if i < 4, do: next_worker()
      end

      assert_receive {:EXIT, ^supervisor, :shutdown}, 2_000
      refute Process.alive?(supervisor)
      assert NativeWorkerOwner.hash(@name, "no restart storm") == {:error, :not_ready}
    end)
  end

  @tag :ordinary
  test "caller death between admission and delivery cannot wedge the slot" do
    with_worker(:normal, fn {_, state, _, _} ->
      parent = self()

      spawn(fn ->
        true = :ets.insert_new(@name, {:request, self(), make_ref()})
        send(parent, :admitted)
      end)

      assert_receive :admitted
      recovered(state.pid)
    end)
  end

  @tag :ordinary
  test "controlling VM SIGKILL leaves no live guardian or native child" do
    [bin, _] = System.argv()
    path = Path.join(System.tmp_dir!(), "zbeam-owned-#{System.unique_integer([:positive])}")

    port =
      Port.open(
        {:spawn_executable, System.find_executable("elixir")},
        [
          :binary,
          :exit_status,
          :stderr_to_stdout,
          args: [
            "--erl",
            "+S 2:2",
            "--name",
            "crash_#{System.pid()}@127.0.0.1",
            "--cookie",
            Atom.to_string(Node.get_cookie()),
            @root <> "/tests/interop/owner_vm_crash.exs",
            bin,
            path
          ]
        ]
      )

    try do
      await(fn -> File.exists?(path) end, 8_000)
      [vm, guard, native] = File.read!(path) |> String.split() |> Enum.map(&String.to_integer/1)
      kill(vm, "KILL")
      await(fn -> not live?(guard) and not live?(native) end)
    after
      close_port(port)
      File.rm(path)
    end
  end

  @tag :epmd
  test "private EPMD loss fails in-flight work and permits a fresh worker" do
    with_worker(:spin, fn {owner, state, _, _} ->
      task = Task.async(fn -> NativeWorkerOwner.hash(@name, "uncertain") end)
      await(fn -> :sys.get_state(owner).pending != nil end)
      kill(String.to_integer(System.fetch_env!("TEST_EPMD_PID")), "KILL")
      assert Task.await(task, 2_000) == {:error, :worker_lost}

      epmd =
        Port.open(
          {:spawn_executable, System.find_executable("epmd")},
          [
            :binary,
            :exit_status,
            args: ["-port", System.fetch_env!("ERL_EPMD_PORT"), "-relaxed_command_check"]
          ]
        )

      try do
        recovered(state.pid)
      after
        if info = Port.info(epmd) do
          kill(Keyword.fetch!(info, :os_pid), "TERM")
          assert_receive {^epmd, {:exit_status, _}}, 2_000
          close_port(epmd)
        end
      end
    end)
  end
end
