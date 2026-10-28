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

    on_exit(fn ->
      if Process.alive?(sup), do: Supervisor.stop(sup)
      await(fn -> not live?(guard) and not live?(native) end)
    end)

    {sup, owner, state, native}
  end

  defp kill(pid, signal) do
    {_, 0} = System.cmd("kill", ["-#{signal}", to_string(pid)], stderr_to_stdout: true)
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
    await(fn -> not live?(new_guard) and not live?(new_native) end)
  end
end
