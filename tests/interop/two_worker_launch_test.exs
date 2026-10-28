Code.require_file("../../examples/two_worker_launch.ex", __DIR__)
Code.require_file("m2c_test_support.exs", __DIR__)
ExUnit.start(trace: true)

defmodule TwoWorkerLaunchTest do
  use ExUnit.Case, async: false
  import M2cTestSupport
  @peer String.to_atom("m2c_launcher_#{System.pid()}@127.0.0.1")
  @bin System.argv() |> hd() |> Path.expand()

  setup do
    Process.flag(:trap_exit, true)
    :ok
  end

  defp discover(actor) do
    ref = make_ref()
    send({:zbeam_workers, @peer}, {self(), ref, {:discover, actor}})

    receive do
      {^ref, {:ok, pid}} -> pid
    after
      3_000 -> flunk("discovery timed out")
    end
  end

  test "owned launcher registers two workers and cleans up before name reuse" do
    assert {:ok, port} = TwoWorkerLaunch.start(@peer, @bin, 3_000)
    {guard, native} = child_pids(port)

    try do
      assert Node.connect(@peer)
      a = discover(:a)
      b = discover(:b)
      assert is_pid(a) and is_pid(b) and a != b
    after
      Node.disconnect(@peer)
      TwoWorkerLaunch.close(port)
    end

    await_dead([guard, native])
    assert {:ok, next} = TwoWorkerLaunch.start(@peer, @bin, 3_000)
    {next_guard, next_native} = child_pids(next)
    TwoWorkerLaunch.close(next)
    await_dead([next_guard, next_native])
  end

  test "a name collision never attaches to or terminates the existing service" do
    assert {:ok, first} = TwoWorkerLaunch.start(@peer, @bin, 3_000)
    {guard, native} = child_pids(first)

    try do
      assert {:error, :name_taken} = TwoWorkerLaunch.start(@peer, @bin, 200)
      assert live?(guard) and live?(native)
      assert Node.connect(@peer)
      assert is_pid(discover(:a))
      assert {:error, :name_taken} = TwoWorkerLaunch.start(@peer, @bin, 200)
      assert live?(native)
    after
      Node.disconnect(@peer)
      TwoWorkerLaunch.close(first)
    end

    await_dead([guard, native])
  end

  test "restart waits for an existing connection and registration to disappear" do
    assert {:ok, first} = TwoWorkerLaunch.start(@peer, @bin, 3_000)
    {guard, native} = child_pids(first)
    assert Node.connect(@peer)
    parent = self()

    starter =
      Task.async(fn ->
        send(parent, :starting)

        case TwoWorkerLaunch.start(@peer, @bin, 3_000) do
          {:ok, port} ->
            true = Port.connect(port, parent)
            {:ok, port}

          error ->
            error
        end
      end)

    try do
      assert_receive :starting, 1_000
      assert Task.yield(starter, 100) == nil
      assert live?(native)
      Node.disconnect(@peer)
      TwoWorkerLaunch.close(first)
      await_dead([guard, native])
      assert {:ok, next} = Task.await(starter, 4_000)
      {next_guard, next_native} = child_pids(next)

      try do
        assert Node.connect(@peer)
        assert is_pid(discover(:a))
      after
        Node.disconnect(@peer)
        TwoWorkerLaunch.close(next)
      end

      await_dead([next_guard, next_native])
    after
      if Port.info(first) != nil, do: TwoWorkerLaunch.close(first)
      Task.shutdown(starter, :brutal_kill)
    end
  end

  test "failed registration and invalid configuration do not publish a child" do
    assert {:error, :not_ready} = TwoWorkerLaunch.start(@peer, "/bin/false", 1_000)
    assert {:error, :not_ready} = TwoWorkerLaunch.start(@peer, "/no/such/zbeam", 1_000)
    assert {:error, :not_ready} = TwoWorkerLaunch.start(:bad_peer, @bin, 1_000)
    assert @peer not in Node.list(:connected)
    assert {:ok, port} = TwoWorkerLaunch.start(@peer, @bin, 3_000)
    {guard, native} = child_pids(port)
    TwoWorkerLaunch.close(port)
    await_dead([guard, native])
  end
end
