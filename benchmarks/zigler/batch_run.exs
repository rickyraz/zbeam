[label, count_arg, bytes_arg, iterations_arg] = System.argv()
count = String.to_integer(count_arg)
size = String.to_integer(bytes_arg)
iterations = String.to_integer(iterations_arg)
true = count in [1, 8, 32] and size >= 0 and size * count <= 1_048_576 and iterations in 1..10_000
true = label in ["nif_dirty", "port_raw", "port_etf", "zbeam"]
workers = System.fetch_env!("ZBEAM_WORKERS")
jobs = for n <- 1..count, do: :binary.copy(<<n>>, size)
packed = IO.iodata_to_binary(jobs)
expected = jobs |> Enum.map(&:crypto.hash(:sha256, &1)) |> IO.iodata_to_binary()
session = :crypto.strong_rand_bytes(16)
name = "batch_#{System.pid()}"
peer = String.to_atom("#{name}@127.0.0.1")

port =
  case label do
    "nif_dirty" ->
      nil

    "zbeam" ->
      Port.open(
        {:spawn_executable, String.to_charlist(Path.join(workers, "zbeam"))},
        [:binary, :exit_status, args: ["serve-batch", name, Atom.to_string(Node.get_cookie())]]
      )

    _ ->
      Port.open(
        {:spawn_executable, String.to_charlist(Path.join(workers, "zbeam-batch-port"))},
        [
          :binary,
          :exit_status,
          {:packet, 4},
          args: [if(label == "port_raw", do: "raw", else: "etf")]
        ]
      )
  end

try do
  if label == "zbeam" do
    true =
      Enum.any?(1..500, fn _ ->
        if Node.connect(peer),
          do: true,
          else:
            (
              Process.sleep(10)
              false
            )
      end)

    true = Node.monitor(peer, true)
  end

  run = fn id ->
    result =
      case label do
        "nif_dirty" ->
          ZbeamResearch.BatchNative.hash_batch(packed, count)

        "zbeam" ->
          send({:sha256_batch, peer}, {session, id, jobs})

          receive do
            {^session, ^id, digest} -> digest
          after
            5000 -> raise "batch timeout"
          end

        _ ->
          input =
            if label == "port_raw",
              do:
                IO.iodata_to_binary([
                  <<count::32>> | Enum.map(jobs, &[<<byte_size(&1)::32>>, &1])
                ]),
              else: :erlang.term_to_binary({session, id, jobs})

          true = Port.command(port, input)

          output =
            receive do
              {^port, {:data, output}} -> output
            after
              5000 -> raise "Port timeout"
            end

          if label == "port_etf" do
            {^session, ^id, digest} = :erlang.binary_to_term(output, [:safe])
            digest
          else
            output
          end
      end

    if result != expected, do: raise("incorrect batch result")
  end

  for id <- 0..99, do: run.(id)
  resources = {label, port, nil}
  cpu_before = ZbeamResearch.Comparison.cpu(resources)
  started = System.monotonic_time(:nanosecond)

  samples =
    for id <- 100..(99 + iterations) do
      before = System.monotonic_time(:nanosecond)
      run.(id)
      System.monotonic_time(:nanosecond) - before
    end

  elapsed = System.monotonic_time(:nanosecond) - started
  cpu_ticks = ZbeamResearch.Comparison.cpu(resources) - cpu_before
  rss_work = ZbeamResearch.Comparison.memory(resources)
  Process.sleep(100)
  rss_idle_100ms = ZbeamResearch.Comparison.memory(resources)
  Process.sleep(900)
  rss_idle_1s = ZbeamResearch.Comparison.memory(resources)
  sorted = Enum.sort(samples)

  IO.puts(
    "RESULT " <>
      JSON.encode!(%{
        label: label,
        jobs_per_batch: count,
        bytes_per_job: size,
        iterations: iterations,
        batch_p50_ns: Enum.at(sorted, div(iterations - 1, 2)),
        batch_p99_ns: Enum.at(sorted, ceil(iterations * 0.99) - 1),
        jobs_s: iterations * count * 1.0e9 / elapsed,
        samples_ns: samples,
        beam_bytes: :erlang.memory(:total),
        cpu_ticks: cpu_ticks,
        rss_work_kib: rss_work,
        rss_idle_100ms_kib: rss_idle_100ms,
        rss_idle_1s_kib: rss_idle_1s,
        note:
          "preformed independent jobs; batch completion latency, no application batch fill wait; one outstanding batch"
      })
  )
after
  if port && Port.info(port) do
    if label == "zbeam" do
      {:os_pid, pid} = Port.info(port, :os_pid)
      System.cmd("kill", ["-TERM", to_string(pid)])
    end

    if Port.info(port), do: Port.close(port)
  end
end
