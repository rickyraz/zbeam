# Linux/WSL development observation; samples are not peak or total-system bounds.
Code.require_file("../examples/two_worker_owner.ex", __DIR__)
Code.require_file("../tests/interop/m2c_test_support.exs", __DIR__)

defmodule OwnerPressure do
  import M2cTestSupport
  @name :owner_pressure_sample

  def run(executable) do
    Process.flag(:trap_exit, true)
    peer = String.to_atom("owner_pressure_#{System.pid()}@127.0.0.1")
    options = [name: @name, peer: peer, executable: Path.expand(executable), timeout_ms: 30_000]
    {:ok, supervisor} = Supervisor.start_link([{TwoWorkerOwner, options}], strategy: :one_for_one)
    owner = Process.whereis(@name)
    {guard, native} = child_pids(:sys.get_state(owner).port)

    try do
      snapshot("idle", owner, native, peer)
      kill(native, "STOP")
      Process.put(:native_paused, true)
      payload = :binary.copy(<<23>>, 256)

      tasks =
        for actor <- [:a, :b], _ <- 1..40 do
          Task.async(fn -> TwoWorkerOwner.hash(@name, actor, payload) end)
        end

      await(fn -> map_size(:sys.get_state(owner).pending) == 2 end)
      results = Task.yield_many(tasks, 2_000)
      78 = Enum.count(results, fn {_, result} -> result == {:ok, {:error, :busy}} end)
      waiting = for {task, nil} <- results, do: task
      2 = length(waiting)
      2 = :ets.info(@name, :size)
      snapshot("80 callers; native stopped", owner, native, peer)
      kill(native, "CONT")
      Process.put(:native_paused, false)
      expected = {:ok, :crypto.hash(:sha256, payload)}
      true = Enum.all?(waiting, &(Task.await(&1, 5_000) == expected))
      snapshot("after resume", owner, native, peer)

      started = System.monotonic_time(:millisecond)

      for i <- 1..1_000, actor <- [:a, :b] do
        input = Integer.to_string(i)
        {:ok, digest} = TwoWorkerOwner.hash(@name, actor, input)
        ^digest = :crypto.hash(:sha256, input)
      end

      IO.inspect(%{requests: 2_000, elapsed_ms: System.monotonic_time(:millisecond) - started},
        label: "short sequential correctness run"
      )

      snapshot("after 2,000 requests", owner, native, peer)
      IO.puts("PASS bounded owner pressure observation")
    after
      if Process.get(:native_paused, false) and live?(native), do: kill(native, "CONT")
      if Process.alive?(supervisor), do: Supervisor.stop(supervisor)
      await_dead([guard, native])
    end
  end

  defp kill(pid, signal) do
    {_, 0} = System.cmd("kill", ["-#{signal}", to_string(pid)], stderr_to_stdout: true)
  end

  defp snapshot(label, owner, native, peer) do
    info = Process.info(owner, [:memory, :message_queue_len])
    memory = :erlang.memory([:total, :binary])

    controller =
      case List.keyfind(:erlang.system_info(:dist_ctrl), peer, 0) do
        {_, port} when is_port(port) -> {:port, :erlang.port_info(port, :queue_size)}
        {_, pid} when is_pid(pid) -> {:process, Process.info(pid, :message_queue_len)}
        _ -> :unavailable
      end

    IO.inspect(
      %{
        owner_memory_bytes: info[:memory],
        owner_message_queue_len: info[:message_queue_len],
        admitted_slots: :ets.info(@name, :size),
        distribution_controller: controller,
        beam_total_bytes: memory[:total],
        beam_binary_bytes: memory[:binary],
        beam_rss_kib: rss(System.pid()),
        native_rss_kib: rss(native)
      },
      label: label
    )
  end

  defp rss(pid) do
    case File.read("/proc/#{pid}/status") do
      {:ok, status} ->
        case Enum.find(String.split(status, "\n"), &String.starts_with?(&1, "VmRSS:")) do
          nil -> nil
          line -> line |> String.split() |> Enum.at(1) |> String.to_integer()
        end

      {:error, _} ->
        nil
    end
  end
end

[executable] = System.argv()
OwnerPressure.run(executable)
