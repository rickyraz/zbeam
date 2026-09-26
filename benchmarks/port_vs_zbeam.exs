[zbeam_bin, port_echo_bin, iterations_arg] = System.argv()
iterations = String.to_integer(iterations_arg)
if iterations < 1, do: raise("iterations must be positive")
warmup = min(100, max(1, div(iterations, 10)))
payload = :binary.copy(<<0x5A>>, 32)
now = fn -> System.monotonic_time(:nanosecond) end
:erlang.system_flag(:scheduler_wall_time, true)

round_trip = fn
  {port, nil} ->
    true = Port.command(port, payload)
    receive do
      {^port, {:data, ^payload}} -> :ok
    after
      3_000 -> raise("Port echo timeout")
    end
  {_port, peer} ->
    send({:echo, peer}, payload)
    receive do
      ^payload -> :ok
    after
      3_000 -> raise("zbeam echo timeout")
    end
end

start_port = fn _count ->
  {Port.open({:spawn_executable, String.to_charlist(port_echo_bin)}, [:binary, {:packet, 4}, :exit_status]), nil}
end
start_zbeam = fn count ->
  name = "zbeam_bench_#{System.pid()}_#{System.unique_integer([:positive])}"
  port = Port.open({:spawn_executable, String.to_charlist(zbeam_bin)}, [
    :binary, :exit_status, :stderr_to_stdout,
    args: ["echo", name, "zbeam_bench_cookie", Integer.to_string(count)]
  ])
  peer = String.to_atom("#{name}@127.0.0.1")
  connected = Enum.any?(1..600, fn _ ->
    if Node.connect(peer), do: true, else: (Process.sleep(5); false)
  end)
  if !connected, do: raise("zbeam connection timeout")
  {port, peer}
end
finish = fn
  {port, nil} -> Port.close(port)
  {port, _peer} = context ->
    # One unmeasured final reply exhausts the explicit child message budget.
    round_trip.(context)
    receive do
      {^port, {:exit_status, 0}} -> :ok
      {^port, {:exit_status, status}} -> raise("zbeam exit status #{status}")
    after
      3_000 -> raise("zbeam exit timeout")
    end
end

# Linux child-process snapshots, not BEAM heap estimates or allocator counts.
rss = fn port ->
  {:os_pid, pid} = Port.info(port, :os_pid)
  case File.read("/proc/#{pid}/status") do
    {:ok, text} ->
      for field <- ["VmRSS", "VmHWM"] do
        case Regex.run(Regex.compile!("^#{field}:\\s+(\\d+) kB$", "m"), text) do
          [_, value] -> String.to_integer(value)
          _ -> "unavailable"
        end
      end
    _ -> ["unavailable", "unavailable"]
  end
end
scheduler_sample = fn ->
  Map.new(:erlang.statistics(:scheduler_wall_time), fn {id, active, total} -> {id, {active, total}} end)
end
busy_percent = fn before, after_sample ->
  {active, total} = Enum.reduce(after_sample, {0, 0}, fn {id, {a, t}}, {sum_a, sum_t} ->
    {old_a, old_t} = Map.fetch!(before, id)
    {sum_a + a - old_a, sum_t + t - old_t}
  end)
  Float.round(100 * active / max(1, total), 3)
end

raw = for {label, start} <- [{"erlang_port", start_port}, {"zbeam_distribution", start_zbeam}] do
  context = {port, _peer} = start.(warmup + iterations + 1)
  Enum.each(1..warmup, fn _ -> round_trip.(context) end)
  before = scheduler_sample.()
  batch_start = now.()
  samples = for _ <- 1..iterations do
    started = now.()
    round_trip.(context)
    now.() - started
  end
  elapsed = now.() - batch_start
  scheduler_busy = busy_percent.(before, scheduler_sample.())
  [rss_kib, hwm_kib] = rss.(port)
  beam_bytes = :erlang.memory(:total)
  sorted = Enum.sort(samples)
  percentile = fn p -> Enum.at(sorted, max(0, ceil(length(sorted) * p) - 1)) end

  restart_started = now.()
  finish.(context)
  restarted = start.(2)
  round_trip.(restarted)
  restart_ns = now.() - restart_started
  finish.(restarted)
  row = [label, iterations, byte_size(payload), percentile.(0.50), percentile.(0.95), percentile.(0.99),
         Float.round(iterations * 1_000_000_000 / elapsed, 1), rss_kib, hwm_kib, beam_bytes, restart_ns, scheduler_busy]
  {row, samples}
end

IO.puts("# OTP #{:erlang.system_info(:otp_release)}; Elixir #{System.version()}; schedulers_online=#{:erlang.system_info(:schedulers_online)}")
IO.puts("implementation\titerations\tpayload_bytes\tp50_ns\tp95_ns\tp99_ns\troundtrips_per_second\tchild_rss_kib\tchild_hwm_kib\tbeam_total_bytes\trestart_ns\tscheduler_busy_pct")
Enum.each(raw, fn {row, _} -> IO.puts(Enum.join(row, "\t")) end)
if path = System.get_env("ZBEAM_BENCH_SAMPLES") do
  lines = for {[label | _], samples} <- raw, {ns, index} <- Enum.with_index(samples, 1), do: "#{label}\t#{index}\t#{ns}\n"
  File.write!(path, ["implementation\titeration\tlatency_ns\n" | lines])
end
