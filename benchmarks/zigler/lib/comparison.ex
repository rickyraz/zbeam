defmodule ZbeamResearch.Comparison do
  @moduledoc false
  alias ZbeamResearch.Native

  def run(label, job, size, count) do
    true = job in ["echo", "sha256"] and size in 1..1_048_576 and count > 0
    input = :binary.copy(<<90>>, size)
    expected = if job == "echo", do: input, else: :crypto.hash(:sha256, input)
    warmup = 100
    context = start(label, job, warmup + count + 1)

    try do
      for _ <- 1..warmup, do: check(call(context, input), expected)
      cpu_before = cpu(context)
      started = System.monotonic_time(:nanosecond)

      samples =
        for _ <- 1..count do
          t = System.monotonic_time(:nanosecond)
          check(call(context, input), expected)
          System.monotonic_time(:nanosecond) - t
        end

      elapsed = System.monotonic_time(:nanosecond) - started
      cpu_after = cpu(context)
      rss_work = memory(context)
      Process.sleep(100)
      rss_idle_100ms = memory(context)
      Process.sleep(900)
      rss_idle_1s = memory(context)
      sorted = Enum.sort(samples)
      percentile = fn p -> Enum.at(sorted, max(0, ceil(count * p) - 1)) end

      result = %{
        label: label,
        job: job,
        bytes: size,
        count: count,
        p50_ns: percentile.(0.50),
        p95_ns: percentile.(0.95),
        p99_ns: percentile.(0.99),
        operations_s: count * 1_000_000_000 / elapsed,
        elapsed_ns: elapsed,
        cpu_ticks: cpu_after - cpu_before,
        rss_work_kib: rss_work,
        rss_idle_100ms_kib: rss_idle_100ms,
        rss_idle_1s_kib: rss_idle_1s,
        samples_ns: samples,
        otp: to_string(:erlang.system_info(:otp_release)),
        elixir: System.version(),
        schedulers: :erlang.system_info(:schedulers_online),
        dirty_cpu: :erlang.system_info(:dirty_cpu_schedulers_online)
      }

      # Exhaust the exact service budget, outside steady-state timing.
      if label == "zbeam_distribution", do: check(call(context, input), expected)
      result
    after
      stop(context)
    end
  end

  def start(label, job, _count) when label in ["port_raw", "port_etf"] do
    bin = if label == "port_raw", do: "zbeam-port-echo", else: "zbeam-port-etf"

    port =
      Port.open(
        {:spawn_executable, String.to_charlist(Path.join(bin_dir(), bin))},
        [:binary, {:packet, 4}, :exit_status, args: [job]]
      )

    {label, port, nil}
  end

  def start("zbeam_distribution", job, count) do
    name = "research_#{System.pid()}_#{System.unique_integer([:positive])}"

    port =
      Port.open(
        {:spawn_executable, String.to_charlist(Path.join(bin_dir(), "zbeam"))},
        [
          :binary,
          :exit_status,
          :stderr_to_stdout,
          args: [
            if(job == "echo", do: "echo", else: "sha256"),
            name,
            Atom.to_string(Node.get_cookie()),
            Integer.to_string(count)
          ]
        ]
      )

    peer = String.to_atom("#{name}@127.0.0.1")

    if !Enum.any?(1..500, fn _ ->
         if Node.connect(peer),
           do: true,
           else:
             (
               Process.sleep(10)
               false
             )
       end) do
      stop({"zbeam_distribution", port, nil})
      raise "worker connection timeout"
    end

    {"zbeam_distribution", port, {peer, if(job == "echo", do: :echo, else: :sha256)}}
  end

  def start(label, job, _count) do
    functions =
      case label do
        "zigler_sync" -> {:echo, :hash}
        "zigler_dirty_cpu" -> {:echo_dirty, :hash_dirty}
        "zigler_threaded" -> {:echo_threaded, :hash_threaded}
        _ -> raise "unknown comparator #{label}"
      end

    fun = elem(functions, if(job == "echo", do: 0, else: 1))
    {:nif, nil, fun}
  end

  def call({:nif, nil, fun}, input), do: apply(Native, fun, [input])

  def call({label, port, nil}, input) when label in ["port_raw", "port_etf"] do
    data = if label == "port_etf", do: :erlang.term_to_binary(input), else: input
    true = Port.command(port, data)

    receive do
      {^port, {:data, reply}} ->
        if label == "port_etf", do: :erlang.binary_to_term(reply, [:safe]), else: reply

      {^port, {:exit_status, status}} ->
        raise "worker exited #{status}"
    after
      5_000 -> raise "Port reply timeout"
    end
  end

  def call({"zbeam_distribution", _port, {peer, name}}, input) do
    send({name, peer}, input)

    receive do
      reply when is_binary(reply) -> reply
    after
      5_000 -> raise "distribution reply timeout"
    end
  end

  def stop({:nif, nil, _}), do: :ok

  def stop({label, port, _}) do
    if info = Port.info(port) do
      # Only this harness-owned Port's still-associated OS child is signaled.
      if label == "zbeam_distribution" do
        pid = Keyword.fetch!(info, :os_pid)
        System.cmd("kill", ["-TERM", Integer.to_string(pid)], stderr_to_stdout: true)
      end

      if Port.info(port), do: Port.close(port)
    end

    :ok
  end

  def check(actual, expected) do
    if actual != expected, do: raise("incorrect worker result")
    :ok
  end

  def bin_dir, do: System.fetch_env!("ZBEAM_WORKERS")

  def pids({_, port, _}) do
    parent = System.pid()

    child =
      if port && Port.info(port),
        do: [to_string(Keyword.fetch!(Port.info(port), :os_pid))],
        else: []

    [parent | child]
  end

  def memory(context) do
    Enum.reduce(pids(context), 0, fn pid, sum ->
      text = File.read!("/proc/#{pid}/status")
      [_, rss] = Regex.run(~r/^VmRSS:\s+(\d+) kB$/m, text)
      sum + String.to_integer(rss)
    end)
  end

  def cpu(context) do
    Enum.reduce(pids(context), 0, fn pid, sum ->
      # The parenthesized comm can contain spaces; subsequent fields begin at state.
      [_, rest] = String.split(File.read!("/proc/#{pid}/stat"), ") ", parts: 2)
      fields = String.split(rest)
      sum + String.to_integer(Enum.at(fields, 11)) + String.to_integer(Enum.at(fields, 12))
    end)
  end
end
