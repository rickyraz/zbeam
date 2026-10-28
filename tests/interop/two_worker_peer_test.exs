Code.require_file("../../examples/two_worker_launch.ex", __DIR__)
Code.require_file("../../examples/two_worker_peer.ex", __DIR__)
ExUnit.start(trace: true)

defmodule TwoWorkerPeerTest do
  use ExUnit.Case, async: false
  @peer String.to_atom("m2c_peer_#{System.pid()}@127.0.0.1")
  @missing String.to_atom("m2c_missing_#{System.pid()}@127.0.0.1")
  @bin System.argv() |> hd() |> Path.expand()

  setup do
    Process.flag(:trap_exit, true)
    :ok
  end

  test "connect discovers and monitors distinct workers on the owned peer" do
    assert {:ok, port} = TwoWorkerLaunch.start(@peer, @bin, 3_000)
    deadline = System.monotonic_time(:millisecond) + 3_000

    try do
      assert {:ok, actors} = TwoWorkerPeer.connect(port, @peer, deadline)
      {a, ma} = actors.a
      {b, mb} = actors.b
      assert node(a) == @peer and node(b) == @peer and a != b
      ref = make_ref()
      send(a, {self(), ref, {:hash, "abc"}})
      assert_receive {^ref, {:ok, digest}}, 2_000
      assert digest == :crypto.hash(:sha256, "abc")
      assert Process.demonitor(ma, [:flush])
      assert Process.demonitor(mb, [:flush])
    after
      Node.monitor(@peer, false)
      Node.disconnect(@peer)
      TwoWorkerLaunch.close(port)
    end
  end

  test "failed bounded connection leaves the actual child unclaimed" do
    assert {:ok, port} = TwoWorkerLaunch.start(@peer, @bin, 3_000)

    try do
      deadline = System.monotonic_time(:millisecond) + 500
      assert {:error, :not_ready} = TwoWorkerPeer.connect(port, @missing, deadline)
      assert @missing not in Node.list(:connected)

      assert {:ok, actors} =
               TwoWorkerPeer.connect(port, @peer, System.monotonic_time(:millisecond) + 3_000)

      assert elem(actors.a, 0) != elem(actors.b, 0)
      for {_, monitor} <- Map.values(actors), do: Process.demonitor(monitor, [:flush])
    after
      Node.monitor(@peer, false)
      Node.disconnect(@peer)
      TwoWorkerLaunch.close(port)
    end
  end
end
