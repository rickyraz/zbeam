ExUnit.start(trace: true)

defmodule TwoWorkerRecoveryTest do
  use ExUnit.Case, async: false
  @root Path.expand("../..", __DIR__)

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

  defp state(pid), do: state_result(File.read("/proc/#{pid}/stat"))

  defp state_result({:ok, stat}) do
    case :binary.matches(stat, ") ") do
      [] ->
        raise "malformed proc stat"

      matches ->
        {index, _} = List.last(matches)
        binary_part(stat, index + 2, 1)
    end
  end

  defp state_result({:error, reason}) when reason in [:enoent, :esrch], do: nil
  defp state_result({:error, reason}), do: raise("proc stat: #{inspect(reason)}")

  defp live?(pid), do: state(pid) not in [nil, "Z", "X", "x"]

  defp native_done(pid) do
    await(fn -> not live?(pid) end)
    Process.put(:natives, List.delete(Process.get(:natives, []), pid))
  end

  defp launch do
    [bin, fault_bin] = System.argv()
    name = "m2_#{System.pid()}_#{System.unique_integer([:positive])}"
    peer = String.to_atom(name <> "@127.0.0.1")

    args =
      if System.get_env("M2_EPMD") do
        [
          fault_bin,
          name,
          Atom.to_string(Node.get_cookie()),
          "workers",
          System.fetch_env!("ERL_EPMD_PORT")
        ]
      else
        [bin, "serve-workers", name, Atom.to_string(Node.get_cookie())]
      end

    port =
      Port.open({:spawn_executable, System.find_executable("python3")}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: [@root <> "/examples/worker_guard.py" | args]
      ])

    {:os_pid, guard} = Port.info(port, :os_pid)
    Process.put(:ports, [port | Process.get(:ports, [])])
    Process.put(:guards, [guard | Process.get(:guards, [])])
    child_file = "/proc/#{guard}/task/#{guard}/children"

    await(fn ->
      case File.read(child_file) do
        {:ok, children} -> String.trim(children) != ""
        _ -> false
      end
    end)

    [native] = File.read!(child_file) |> String.split() |> Enum.map(&String.to_integer/1)
    Process.put(:natives, [native | Process.get(:natives, [])])
    await(fn -> Node.connect(peer) end)
    true = Node.monitor(peer, true)
    {port, peer, native}
  end

  defp call(to, command) do
    ref = make_ref()
    :ok = :erlang.send(to, {self(), ref, command}, [:noconnect, :nosuspend])

    receive do
      {^ref, value} -> value
    after
      5_000 -> flunk("worker request timed out")
    end
  end

  defp close(port) do
    Port.close(port)
  rescue
    error in ArgumentError -> if Port.info(port) != nil, do: reraise(error, __STACKTRACE__)
  end

  setup do
    Process.flag(:trap_exit, true)
    Process.put(:ports, [])
    Process.put(:guards, [])
    Process.put(:natives, [])
    :ok
  end

  test "proc-state oracle handles terminal races without hiding errors" do
    for value <- ["Z", "X", "x", "T", "R"] do
      assert state_result({:ok, "123 (name) Z tricky) #{value} 1"}) == value
    end

    assert state_result({:error, :enoent}) == nil
    assert state_result({:error, :esrch}) == nil
    assert_raise RuntimeError, fn -> state_result({:error, :eacces}) end
    assert_raise RuntimeError, fn -> state_result({:ok, "malformed"}) end
  end

  test "owned process loss fails uncertain work and replacement never replays" do
    vm = System.pid()

    probe =
      spawn(fn ->
        receive do
          {from, ref} -> send(from, ref)
        end
      end)

    try do
      if System.get_env("M2_EPMD") do
        {port, peer, native} = launch()
        {_, 0} = System.cmd("kill", ["-TERM", System.fetch_env!("TEST_EPMD_PID")])
        assert_receive {:nodedown, ^peer}, 5_000
        assert_receive {^port, {:exit_status, _}}, 5_000
        native_done(native)
        close(port)
      else
        {port, peer, native} = launch()
        {:ok, a} = call({:zbeam_workers, peer}, {:discover, :a})
        {:ok, b} = call({:zbeam_workers, peer}, {:discover, :b})
        assert a != b
        assert call(a, {:hash, "abc"}) == {:ok, :crypto.hash(:sha256, "abc")}
        monitor_a = Process.monitor(a)
        monitor_b = Process.monitor(b)
        {_, 0} = System.cmd("kill", ["-STOP", to_string(native)])
        await(fn -> state(native) in ["T", "t"] end)
        old_ref = make_ref()
        :ok = :erlang.send(a, {self(), old_ref, {:hash, "uncertain"}}, [:noconnect, :nosuspend])
        refute_receive {^old_ref, _}, 50
        {_, 0} = System.cmd("kill", ["-KILL", to_string(native)])
        assert_receive {:nodedown, ^peer}, 5_000
        assert_receive {:DOWN, ^monitor_a, :process, ^a, :noconnection}, 5_000
        assert_receive {:DOWN, ^monitor_b, :process, ^b, :noconnection}, 5_000
        assert_receive {^port, {:exit_status, _}}, 5_000
        native_done(native)
        close(port)
        {replacement, next_peer, next_native} = launch()
        {:ok, next_a} = call({:zbeam_workers, next_peer}, {:discover, :a})
        {:ok, next_b} = call({:zbeam_workers, next_peer}, {:discover, :b})
        assert next_a != a and next_b != b
        assert call(next_a, {:hash, "fresh a"}) == {:ok, :crypto.hash(:sha256, "fresh a")}
        assert call(next_b, {:hash, "fresh b"}) == {:ok, :crypto.hash(:sha256, "fresh b")}
        refute_receive {^old_ref, _}, 100
        close(replacement)
        native_done(next_native)
      end

      assert System.pid() == vm
      ping = make_ref()
      send(probe, {self(), ping})
      assert_receive ^ping, 500
    after
      Process.exit(probe, :kill)
      for port <- Process.get(:ports, []), do: close(port)
      for native <- Process.get(:natives, []), do: await(fn -> not live?(native) end)
      for guard <- Process.get(:guards, []), do: await(fn -> not live?(guard) end)
    end
  end
end
