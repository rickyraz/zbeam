Code.require_file("../../examples/two_worker_owner.ex", __DIR__)
Code.require_file("m2c_test_support.exs", __DIR__)
ExUnit.start(trace: true)

defmodule TwoWorkerOwnerTest do
  use ExUnit.Case, async: false
  import M2cTestSupport
  @name :m2c_owner_test
  @peer String.to_atom("m2c_owner_#{System.pid()}@127.0.0.1")
  @bin System.argv() |> hd() |> Path.expand()

  defp owned(owner) do
    state = :sys.get_state(owner)
    {guard, native} = child_pids(state.port)
    {state, guard, native}
  end

  defp start(timeout \\ 5_000) do
    Process.flag(:trap_exit, true)
    opts = [name: @name, peer: @peer, executable: @bin, timeout_ms: timeout]

    {:ok, sup} =
      Supervisor.start_link([{TwoWorkerOwner, opts}],
        strategy: :one_for_one,
        max_restarts: 3,
        max_seconds: 5
      )

    Process.unlink(sup)
    owner = Process.whereis(@name)
    {state, guard, native} = owned(owner)
    old_checked = :atomics.new(1, [])
    Process.put(:old_checked, old_checked)
    Process.put(:old_guard, guard)

    on_exit(fn ->
      if Process.alive?(sup), do: Supervisor.stop(sup)
      if :atomics.get(old_checked, 1) == 0, do: await_dead([guard, native])
    end)

    {sup, owner, state, native}
  end

  defp kill(pid, signal) do
    {_, 0} = System.cmd("kill", ["-#{signal}", to_string(pid)], stderr_to_stdout: true)
  end

  defp recovered(owner, old, native) do
    await(fn -> is_pid(Process.whereis(@name)) and Process.whereis(@name) != owner end)
    replacement = Process.whereis(@name)
    {state, guard, child} = owned(replacement)
    assert elem(state.actors.a, 0) != elem(old.actors.a, 0)
    assert elem(state.actors.b, 0) != elem(old.actors.b, 0)
    await_dead([Process.get(:old_guard), native])
    :atomics.put(Process.get(:old_checked), 1, 1)
    {replacement, state, guard, child}
  end

  defp stop_and_check(sup, guard, native) do
    Supervisor.stop(sup)
    await_dead([guard, native])
  end

  test "exact hashes, per-actor admission and input bounds" do
    {_, owner, _, native} = start()
    assert TwoWorkerOwner.hash(@name, :a, "abc") == {:ok, :crypto.hash(:sha256, "abc")}
    assert TwoWorkerOwner.hash(@name, :b, <<>>) == {:ok, :crypto.hash(:sha256, <<>>)}
    maximum = :binary.copy(<<42>>, 1_048_576)
    assert TwoWorkerOwner.hash(@name, :b, maximum) == {:ok, :crypto.hash(:sha256, maximum)}
    assert TwoWorkerOwner.hash(@name, :a, :bad) == {:error, :invalid_input}

    assert TwoWorkerOwner.hash(@name, :a, :binary.copy(<<0>>, 1_048_577)) ==
             {:error, :invalid_input}

    kill(native, "STOP")

    try do
      a = Task.async(fn -> TwoWorkerOwner.hash(@name, :a, "first") end)
      b = Task.async(fn -> TwoWorkerOwner.hash(@name, :b, "second") end)
      await(fn -> map_size(:sys.get_state(owner).pending) == 2 end)
      assert TwoWorkerOwner.hash(@name, :a, "excess") == {:error, :busy}
      assert TwoWorkerOwner.hash(@name, :b, "excess") == {:error, :busy}
      kill(native, "CONT")
      Process.put(:native_resumed, true)
      assert Task.await(a, 2_000) == {:ok, :crypto.hash(:sha256, "first")}
      assert Task.await(b, 2_000) == {:ok, :crypto.hash(:sha256, "second")}
    after
      if not Process.get(:native_resumed, false) and live?(native), do: kill(native, "CONT")
    end
  end

  test "simultaneous callers admit only one payload per actor" do
    {_, owner, _, native} = start()
    payload = :binary.copy(<<23>>, 256)
    kill(native, "STOP")

    try do
      tasks =
        for actor <- [:a, :b], _ <- 1..40 do
          Task.async(fn -> TwoWorkerOwner.hash(@name, actor, payload) end)
        end

      await(fn -> map_size(:sys.get_state(owner).pending) == 2 end)
      results = Task.yield_many(tasks, 2_000)
      assert Enum.count(results, fn {_, result} -> result == {:ok, {:error, :busy}} end) == 78
      waiting = for {task, nil} <- results, do: task
      assert length(waiting) == 2
      assert :ets.info(@name, :size) == 2
      kill(native, "CONT")
      Process.put(:load_resumed, true)
      expected = {:ok, :crypto.hash(:sha256, payload)}
      assert Enum.all?(waiting, &(Task.await(&1, 2_000) == expected))
    after
      if not Process.get(:load_resumed, false) and live?(native), do: kill(native, "CONT")
    end
  end

  test "failed table creation disconnects and permits a clean later start" do
    Process.flag(:trap_exit, true)
    table = :ets.new(@name, [:named_table, :public, :set])
    options = [name: @name, peer: @peer, executable: @bin]
    assert {:error, :not_ready} = TwoWorkerOwner.start_link(options)
    :ets.delete(table)
    refute @peer in Node.list(:connected)
    start()
    assert TwoWorkerOwner.hash(@name, :a, "ready") == {:ok, :crypto.hash(:sha256, "ready")}
  end

  test "controlled actor stop leaves its sibling usable" do
    {_, owner, state, _} = start()
    {a, _} = state.actors.a
    ref = make_ref()
    send(a, {self(), ref, :stop})
    assert_receive {^ref, :ok}, 2_000
    await(fn -> :sys.get_state(owner).actors.a == nil end)
    assert TwoWorkerOwner.hash(@name, :a, "retired") == {:error, :unavailable}
    assert TwoWorkerOwner.hash(@name, :b, "alive") == {:ok, :crypto.hash(:sha256, "alive")}
  end

  test "caller death before delivery retires the old owner and both PIDs" do
    {sup, owner, old, native} = start()
    parent = self()

    {caller, monitor} =
      spawn_monitor(fn ->
        assert {:ok, ^owner, _, _} = TwoWorkerAdmission.claim(@name, :a, "claimed")
        send(parent, :claimed)
      end)

    assert_receive :claimed, 1_000
    assert_receive {:DOWN, ^monitor, :process, ^caller, :normal}, 1_000
    {_, _, guard, child} = recovered(owner, old, native)
    assert TwoWorkerOwner.hash(@name, :b, "fresh") == {:ok, :crypto.hash(:sha256, "fresh")}
    stop_and_check(sup, guard, child)
  end

  test "caller death during work fails the sibling's uncertain request" do
    {sup, owner, old, native} = start()
    kill(native, "STOP")
    caller = spawn(fn -> TwoWorkerOwner.hash(@name, :a, "uncertain") end)
    b = Task.async(fn -> TwoWorkerOwner.hash(@name, :b, "uncertain sibling") end)
    await(fn -> map_size(:sys.get_state(owner).pending) == 2 end)
    Process.exit(caller, :kill)
    assert Task.await(b, 2_000) == {:error, :worker_lost}
    {_, _, guard, child} = recovered(owner, old, native)
    assert TwoWorkerOwner.hash(@name, :a, "fresh") == {:ok, :crypto.hash(:sha256, "fresh")}
    stop_and_check(sup, guard, child)
  end

  test "disconnect discards both requests and old references cannot answer a replacement" do
    {sup, owner, old, native} = start()
    kill(native, "STOP")
    a = Task.async(fn -> TwoWorkerOwner.hash(@name, :a, "uncertain a") end)
    b = Task.async(fn -> TwoWorkerOwner.hash(@name, :b, "uncertain b") end)
    await(fn -> map_size(:sys.get_state(owner).pending) == 2 end)
    {_, _, old_ref, _, _} = :sys.get_state(owner).pending.a
    assert Node.disconnect(@peer)
    assert Task.await(a, 2_000) == {:error, :worker_lost}
    assert Task.await(b, 2_000) == {:error, :worker_lost}
    {replacement, _, guard, child} = recovered(owner, old, native)
    kill(child, "STOP")

    try do
      fresh = Task.async(fn -> TwoWorkerOwner.hash(@name, :a, "fresh") end)
      await(fn -> Map.has_key?(:sys.get_state(replacement).pending, :a) end)
      {_, _, new_ref, _, _} = :sys.get_state(replacement).pending.a
      send(replacement, {old_ref, {:ok, <<0::256>>}})
      assert elem(:sys.get_state(replacement).pending.a, 2) == new_ref
      kill(child, "CONT")
      Process.put(:replacement_resumed, true)
      assert Task.await(fresh, 2_000) == {:ok, :crypto.hash(:sha256, "fresh")}
    after
      if not Process.get(:replacement_resumed, false) and live?(child), do: kill(child, "CONT")
    end

    stop_and_check(sup, guard, child)
  end

  test "owner kill fails both requests and the guardian kills the owned child" do
    {sup, owner, old, native} = start()
    kill(native, "STOP")
    a = Task.async(fn -> TwoWorkerOwner.hash(@name, :a, "uncertain a") end)
    b = Task.async(fn -> TwoWorkerOwner.hash(@name, :b, "uncertain b") end)
    await(fn -> map_size(:sys.get_state(owner).pending) == 2 end)
    Process.exit(owner, :kill)
    assert Task.await(a, 2_000) == {:error, :worker_lost}
    assert Task.await(b, 2_000) == {:error, :worker_lost}
    {_, _, guard, child} = recovered(owner, old, native)
    assert TwoWorkerOwner.hash(@name, :b, "fresh") == {:ok, :crypto.hash(:sha256, "fresh")}
    stop_and_check(sup, guard, child)
  end

  test "one timeout fails both uncertain requests and restarts without replay" do
    {sup, owner, old, native} = start(500)
    kill(native, "STOP")
    a = Task.async(fn -> TwoWorkerOwner.hash(@name, :a, "uncertain a") end)
    await(fn -> Map.has_key?(:sys.get_state(owner).pending, :a) end)
    b = Task.async(fn -> TwoWorkerOwner.hash(@name, :b, "uncertain b") end)
    await(fn -> map_size(:sys.get_state(owner).pending) == 2 end)
    assert Task.await(a, 2_000) == {:error, :timeout}
    assert Task.await(b, 2_000) == {:error, :worker_lost}
    await(fn -> is_pid(Process.whereis(@name)) and Process.whereis(@name) != owner end)
    {new, new_guard, new_native} = owned(Process.whereis(@name))
    assert elem(new.actors.a, 0) != elem(old.actors.a, 0)
    assert TwoWorkerOwner.hash(@name, :b, "fresh") == {:ok, :crypto.hash(:sha256, "fresh")}
    assert Process.alive?(sup)
    Supervisor.stop(sup)
    await_dead([new_guard, new_native])
  end
end
