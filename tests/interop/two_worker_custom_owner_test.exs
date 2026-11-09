Code.require_file("../../examples/two_worker_owner.ex", __DIR__)
Code.require_file("m2c_test_support.exs", __DIR__)
ExUnit.start(trace: true)

defmodule TwoWorkerCustomOwnerTest do
  use ExUnit.Case, async: false
  import M2cTestSupport
  @name :custom_owner_test
  @peer String.to_atom("custom_owner_#{System.pid()}@127.0.0.1")
  [custom, sha256] = System.argv() |> Enum.map(&Path.expand/1)
  @custom custom
  @sha256 sha256

  defp start(options \\ []) do
    Process.flag(:trap_exit, true)
    defaults = [name: @name, peer: @peer, executable: @custom, profile: :custom]

    {:ok, sup} =
      Supervisor.start_link([{TwoWorkerOwner, Keyword.merge(defaults, options)}],
        strategy: :one_for_one,
        max_restarts: 3,
        max_seconds: 5
      )

    Process.unlink(sup)
    owner = Process.whereis(@name)
    state = :sys.get_state(owner)
    {guard, native} = child_pids(state.port)

    on_exit(fn ->
      if Process.alive?(sup), do: Supervisor.stop(sup)
      await_dead([guard, native])
    end)

    {sup, owner, state, native}
  end

  defp kill(pid, signal) do
    {_, 0} = System.cmd("kill", ["-#{signal}", to_string(pid)], stderr_to_stdout: true)
  end

  test "custom calls reach both actors and the other profile's command is unsupported" do
    {_, _, _, _} = start()
    assert TwoWorkerOwner.call(@name, :a, "hello") == {:ok, "HELLO"}
    assert TwoWorkerOwner.call(@name, :b, <<>>) == {:ok, <<>>}
    maximum = :binary.copy("z", 32)
    assert TwoWorkerOwner.call(@name, :b, maximum) == {:ok, :binary.copy("Z", 32)}
    assert TwoWorkerOwner.hash(@name, :a, "abc") == {:error, :unsupported}
    assert :ets.info(@name, :size) == 0
    assert TwoWorkerOwner.call(@name, :a, "still usable") == {:ok, "STILL USABLE"}

    assert TwoWorkerOwner.call(@name, :a, :binary.copy(<<0>>, 1_048_577)) ==
             {:error, :invalid_input}

    assert TwoWorkerOwner.call(@name, :c, "x") == {:error, :invalid_input}
  end

  test "the SHA-256 owner rejects call without consuming admission" do
    {_, _, _, _} = start(executable: @sha256, profile: :sha256)
    assert TwoWorkerOwner.call(@name, :a, "abc") == {:error, :unsupported}
    assert TwoWorkerOwner.hash(@name, :a, "abc") == {:ok, :crypto.hash(:sha256, "abc")}
  end

  test "an unknown profile does not start a child" do
    Process.flag(:trap_exit, true)
    options = [name: @name, peer: @peer, executable: @custom, profile: :other]
    assert {:error, :not_ready} = TwoWorkerOwner.start_link(options)
    refute @peer in Node.list(:connected)
  end

  test "admission, handler failure and stop retire only the affected actor" do
    {_, owner, _, native} = start()
    kill(native, "STOP")

    try do
      first = Task.async(fn -> TwoWorkerOwner.call(@name, :a, "first") end)
      await(fn -> Map.has_key?(:sys.get_state(owner).pending, :a) end)
      assert TwoWorkerOwner.call(@name, :a, "excess") == {:error, :busy}
      assert TwoWorkerOwner.stop(@name, :a) == {:error, :busy}
      kill(native, "CONT")
      Process.put(:custom_resumed, true)
      assert Task.await(first, 2_000) == {:ok, "FIRST"}
    after
      if not Process.get(:custom_resumed, false) and live?(native), do: kill(native, "CONT")
    end

    assert TwoWorkerOwner.call(@name, :a, :binary.copy("a", 33)) == {:error, :handler_failed}
    assert TwoWorkerOwner.call(@name, :a, "retired") == {:error, :unavailable}
    assert TwoWorkerOwner.call(@name, :b, "sibling") == {:ok, "SIBLING"}
    assert TwoWorkerOwner.stop(@name, :b) == :ok
    assert TwoWorkerOwner.call(@name, :b, "retired") == {:error, :unavailable}
    assert Process.whereis(@name) == owner
  end

  test "native loss fails uncertain calls and a replacement serves only fresh work" do
    {sup, owner, old, native} = start()
    kill(native, "STOP")
    a = Task.async(fn -> TwoWorkerOwner.call(@name, :a, "uncertain a") end)
    b = Task.async(fn -> TwoWorkerOwner.call(@name, :b, "uncertain b") end)
    await(fn -> map_size(:sys.get_state(owner).pending) == 2 end)
    kill(native, "KILL")
    assert Task.await(a, 2_000) == {:error, :worker_lost}
    assert Task.await(b, 2_000) == {:error, :worker_lost}
    replacement = await_replacement(@name, owner)
    state = :sys.get_state(replacement)
    assert state.pending == %{}
    assert elem(state.actors.a, 0) != elem(old.actors.a, 0)
    assert elem(state.actors.b, 0) != elem(old.actors.b, 0)
    {guard, child} = child_pids(state.port)
    assert child != native
    assert TwoWorkerOwner.call(@name, :a, "fresh") == {:ok, "FRESH"}
    Supervisor.stop(sup)
    await_dead([guard, child])
  end
end
