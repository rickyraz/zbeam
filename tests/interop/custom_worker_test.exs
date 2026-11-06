Code.require_file("../../examples/two_worker_launch.ex", __DIR__)
Code.require_file("../../examples/two_worker_peer.ex", __DIR__)
Code.require_file("m2c_test_support.exs", __DIR__)
ExUnit.start(trace: true)

defmodule CustomWorkerTest do
  use ExUnit.Case, async: false
  import M2cTestSupport
  @peer String.to_atom("custom_test_#{System.pid()}@127.0.0.1")
  [custom, standard] = System.argv()
  @custom Path.expand(custom)
  @standard Path.expand(standard)

  defp with_worker(binary, command, test) do
    Process.flag(:trap_exit, true)
    {:ok, port} = TwoWorkerLaunch.start(@peer, binary, 3_000, command)
    {guard, native} = child_pids(port)

    try do
      test.(port, native)
    after
      Node.monitor(@peer, false)
      Node.disconnect(@peer)
      TwoWorkerLaunch.close(port)
      await_dead([guard, native])
    end
  end

  defp connect(port) do
    deadline = System.monotonic_time(:millisecond) + 5_000
    {:ok, actors} = TwoWorkerPeer.connect(port, @peer, deadline)
    actors
  end

  defp request(to, command) do
    ref = make_ref()
    :ok = :erlang.send(to, {self(), ref, command}, [:noconnect, :nosuspend])

    receive do
      {^ref, value} -> value
    after
      5_000 -> flunk("custom request timed out")
    end
  end

  defp disconnect(actors) do
    for {_, {_, monitor}} <- actors, do: Process.demonitor(monitor, [:flush])
    Node.monitor(@peer, false)
    Node.disconnect(@peer)
    await(fn -> @peer not in Node.list(:connected) end)
  end

  test "custom calls survive reconnect, reject bad input and retire independently" do
    with_worker(@custom, "serve-custom", fn port, _ ->
      actors = connect(port)
      {a, _} = actors.a
      {b, _} = actors.b
      assert a != b
      assert request(a, {:call, <<>>}) == {:ok, <<>>}
      assert request(a, {:call, :binary.copy("a", 32)}) == {:ok, :binary.copy("A", 32)}
      assert request(b, {:call, "world"}) == {:ok, "WORLD"}
      assert request(a, {:hash, "abc"}) == {:error, :bad_request}
      assert request(a, {:call, :not_binary}) == {:error, :bad_request}

      disconnect(actors)
      actors = connect(port)
      assert elem(actors.a, 0) == a and elem(actors.b, 0) == b
      assert request(b, {:call, "fresh"}) == {:ok, "FRESH"}

      ref = make_ref()
      oversized = :binary.copy(<<42>>, 1_048_577)
      assert :ok = :erlang.send(a, {self(), ref, {:call, oversized}}, [:noconnect, :nosuspend])
      peer = @peer
      assert_receive {:nodedown, ^peer}, 5_000
      disconnect(actors)
      actors = connect(port)
      assert elem(actors.a, 0) == a and elem(actors.b, 0) == b
      {_, a_monitor} = actors.a
      {_, b_monitor} = actors.b
      assert request(a, {:call, :binary.copy("a", 33)}) == {:error, :handler_failed}
      assert_receive {:DOWN, ^a_monitor, :process, ^a, :handler_failed}, 5_000
      assert request({:zbeam_workers, @peer}, {:discover, :a}) == {:error, :noproc}
      assert request(b, {:call, "still alive"}) == {:ok, "STILL ALIVE"}
      assert request(b, :stop) == :ok
      assert_receive {:DOWN, ^b_monitor, :process, ^b, :normal}, 5_000
      assert request({:zbeam_workers, @peer}, {:discover, :b}) == {:error, :noproc}
    end)
  end

  test "the original service rejects call and retains exact SHA-256" do
    with_worker(@standard, "serve-workers", fn port, _ ->
      {a, _} = connect(port).a
      assert request(a, {:call, "abc"}) == {:error, :bad_request}
      assert request(a, {:hash, "abc"}) == {:ok, :crypto.hash(:sha256, "abc")}
    end)
  end

  test "native loss leaves uncertain work unreplayed and preserves the BEAM VM" do
    {old, ref} =
      with_worker(@custom, "serve-custom", fn port, native ->
        {a, _} = connect(port).a
        vm_pid = System.pid()
        parent = self()
        other = spawn(fn -> receive do :ping -> send(parent, :pong) end end)

        try do
          {_, 0} = System.cmd("kill", ["-STOP", to_string(native)], stderr_to_stdout: true)
          ref = make_ref()
          assert :ok = :erlang.send(a, {self(), ref, {:call, "uncertain"}}, [:noconnect, :nosuspend])
          {_, 0} = System.cmd("kill", ["-KILL", to_string(native)], stderr_to_stdout: true)
          peer = @peer
          assert_receive {:nodedown, ^peer}, 5_000
          assert System.pid() == vm_pid
          assert Process.alive?(other)
          send(other, :ping)
          assert_receive :pong, 1_000
          {a, ref}
        after
          if Process.alive?(other), do: Process.exit(other, :kill)
        end
      end)

    with_worker(@custom, "serve-custom", fn port, _ ->
      {fresh, _} = connect(port).a
      assert fresh != old
      assert request(fresh, {:call, "fresh"}) == {:ok, "FRESH"}
      refute_receive {^ref, _}, 100
    end)
  end
end
