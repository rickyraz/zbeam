# Linux soak: concurrent exact calls through one supervised owner for a fixed time.
# Usage: owner_soak.exs EXECUTABLE sha256|custom SECONDS CALLERS_PER_ACTOR
Code.require_file("../examples/two_worker_owner.ex", __DIR__)
Code.require_file("../tests/interop/m2c_test_support.exs", __DIR__)

defmodule OwnerSoak do
  import M2cTestSupport
  @name :owner_soak
  @sizes %{sha256: [0, 1, 32, 256, 4_096, 65_536, 1_048_576], custom: [0, 1, 32, 33, 256, 4_096, 65_536]}

  def run(executable, profile, seconds, callers) do
    Process.flag(:trap_exit, true)
    peer = String.to_atom("owner_soak_#{System.pid()}@127.0.0.1")

    options = [
      name: @name,
      peer: peer,
      executable: Path.expand(executable),
      profile: profile,
      timeout_ms: 30_000
    ]

    {:ok, supervisor} = Supervisor.start_link([{TwoWorkerOwner, options}], strategy: :one_for_one)
    owner = Process.whereis(@name)
    {guard, native} = child_pids(:sys.get_state(owner).port)
    deadline = System.monotonic_time(:millisecond) + seconds * 1_000
    sampler = spawn_link(fn -> sample(owner, native, %{}) end)

    try do
      tasks =
        for actor <- [:a, :b], caller <- 1..callers do
          Task.async(fn ->
            :rand.seed(:exsss, {caller, if(actor == :a, do: 1, else: 2), 7})
            loop(profile, actor, deadline, %{ok: 0, busy: 0, latencies: []})
          end)
        end

      counts = Enum.map(tasks, &Task.await(&1, :infinity))
      send(sampler, {:stop, self()})
      samples = receive do: ({:samples, samples} -> samples)
      latencies = counts |> Enum.flat_map(& &1.latencies) |> Enum.sort()
      ok = Enum.sum(Enum.map(counts, & &1.ok))
      true = ok > 0 and Process.whereis(@name) == owner

      IO.inspect(
        Map.merge(samples, %{
          profile: profile,
          seconds: seconds,
          callers_per_actor: callers,
          ok: ok,
          busy: Enum.sum(Enum.map(counts, & &1.busy)),
          ok_per_second: div(ok, seconds),
          latency_us: percentiles(latencies)
        }),
        label: "owner soak",
        limit: :infinity
      )

      IO.puts("PASS owner soak #{profile}: exact results, no failures, no owner restart")
    after
      if Process.alive?(supervisor), do: Supervisor.stop(supervisor)
      await_dead([guard, native])
    end
  end

  defp loop(profile, actor, deadline, acc) do
    if System.monotonic_time(:millisecond) >= deadline do
      acc
    else
      input = :rand.bytes(Enum.random(@sizes[profile]))
      started = System.monotonic_time(:microsecond)

      case request(profile, actor, input) do
        {:ok, output} ->
          ^output = expected(profile, input)
          elapsed = System.monotonic_time(:microsecond) - started
          # Keep one latency in eight to bound harness memory on long runs.
          latencies = if rem(acc.ok, 8) == 0, do: [elapsed | acc.latencies], else: acc.latencies
          loop(profile, actor, deadline, %{acc | ok: acc.ok + 1, latencies: latencies})

        {:error, :busy} ->
          Process.sleep(1)
          loop(profile, actor, deadline, %{acc | busy: acc.busy + 1})

        other ->
          raise "soak failure on #{actor}: #{inspect(other)}"
      end
    end
  end

  defp request(:sha256, actor, input), do: TwoWorkerOwner.hash(@name, actor, input)
  defp request(:custom, actor, input), do: TwoWorkerOwner.call(@name, actor, input)

  defp expected(:sha256, input), do: :crypto.hash(:sha256, input)
  defp expected(:custom, input), do: for(<<c <- input>>, into: <<>>, do: <<upper(c)>>)

  defp upper(c) when c in ?a..?z, do: c - 32
  defp upper(c), do: c

  defp sample(owner, native, acc) do
    receive do
      {:stop, from} -> send(from, {:samples, acc})
    after
      1_000 ->
        now = %{
          native_rss_kib: status(native, "VmRSS:"),
          native_hwm_kib: status(native, "VmHWM:"),
          beam_rss_kib: status(System.pid(), "VmRSS:"),
          beam_total_bytes: :erlang.memory(:total),
          owner_queue: Process.info(owner, :message_queue_len) |> elem(1)
        }

        sample(owner, native, Map.merge(acc, Map.new(now, fn {k, v} -> {k, range(acc[k], v)} end)))
    end
  end

  defp range(nil, v), do: %{first: v, min: v, max: v, last: v}
  defp range(r, v), do: %{r | min: min(r.min, v), max: max(r.max, v), last: v}

  defp status(pid, field) do
    "/proc/#{pid}/status"
    |> File.read!()
    |> String.split("\n")
    |> Enum.find(&String.starts_with?(&1, field))
    |> String.split()
    |> Enum.at(1)
    |> String.to_integer()
  end

  defp percentiles([]), do: %{}

  defp percentiles(sorted) do
    at = fn p -> Enum.at(sorted, min(length(sorted) - 1, div(length(sorted) * p, 100))) end
    %{samples: length(sorted), p50: at.(50), p99: at.(99), max: List.last(sorted)}
  end
end

[executable, profile, seconds, callers] = System.argv()
profile = %{"sha256" => :sha256, "custom" => :custom} |> Map.fetch!(profile)
[seconds, callers] = Enum.map([seconds, callers], &String.to_integer/1)
true = seconds > 0 and callers > 0
OwnerSoak.run(executable, profile, seconds, callers)
