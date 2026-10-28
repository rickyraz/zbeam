Code.require_file("../../examples/two_worker_launch.ex", __DIR__)
ExUnit.start(trace: true)

defmodule TwoWorkerLaunchTest do
  use ExUnit.Case, async: false
  @peer String.to_atom("m2c_launcher_#{System.pid()}@127.0.0.1")
  @bin System.argv() |> hd() |> Path.expand()

  setup do
    Process.flag(:trap_exit, true)
    :ok
  end

  defp await(predicate, timeout \\ 5_000) do
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
      {:ok, stat} ->
        [{index, _} | _] = Enum.reverse(:binary.matches(stat, ") "))
        binary_part(stat, index + 2, 1) not in ["Z", "X", "x"]

      {:error, reason} when reason in [:enoent, :esrch] ->
        false

      {:error, reason} ->
        raise "proc stat: #{inspect(reason)}"
    end
  end

  defp owned(port) do
    {:os_pid, guard} = Port.info(port, :os_pid)
    path = "/proc/#{guard}/task/#{guard}/children"

    await(fn ->
      case File.read(path) do
        {:ok, data} -> String.trim(data) != ""
        _ -> false
      end
    end)

    [native] = File.read!(path) |> String.split() |> Enum.map(&String.to_integer/1)
    {guard, native}
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
    {guard, native} = owned(port)

    try do
      assert Node.connect(@peer)
      a = discover(:a)
      b = discover(:b)
      assert is_pid(a) and is_pid(b) and a != b
    after
      Node.disconnect(@peer)
      TwoWorkerLaunch.close(port)
    end

    await(fn -> not live?(guard) and not live?(native) end)
    assert {:ok, next} = TwoWorkerLaunch.start(@peer, @bin, 3_000)
    {next_guard, next_native} = owned(next)
    TwoWorkerLaunch.close(next)
    await(fn -> not live?(next_guard) and not live?(next_native) end)
  end

  test "a name collision never attaches to or terminates the existing service" do
    assert {:ok, first} = TwoWorkerLaunch.start(@peer, @bin, 3_000)
    {guard, native} = owned(first)

    try do
      assert {:error, :name_taken} = TwoWorkerLaunch.start(@peer, @bin, 200)
      assert live?(guard) and live?(native)
      assert Node.connect(@peer)
      assert is_pid(discover(:a))
      assert {:error, :not_ready} = TwoWorkerLaunch.start(@peer, @bin, 200)
      assert live?(native)
    after
      Node.disconnect(@peer)
      TwoWorkerLaunch.close(first)
    end

    await(fn -> not live?(guard) and not live?(native) end)
  end

  test "failed registration and invalid configuration do not publish a child" do
    assert {:error, :not_ready} = TwoWorkerLaunch.start(@peer, "/bin/false", 1_000)
    assert {:error, :not_ready} = TwoWorkerLaunch.start(@peer, "/no/such/zbeam", 1_000)
    assert {:error, :not_ready} = TwoWorkerLaunch.start(:bad_peer, @bin, 1_000)
    assert @peer not in Node.list(:connected)
    assert {:ok, port} = TwoWorkerLaunch.start(@peer, @bin, 3_000)
    {guard, native} = owned(port)
    TwoWorkerLaunch.close(port)
    await(fn -> not live?(guard) and not live?(native) end)
  end
end
