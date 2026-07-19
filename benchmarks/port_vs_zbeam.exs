[zbeam_bin, port_echo_bin, iterations_arg] = System.argv()
iterations = String.to_integer(iterations_arg)
if iterations < 1, do: raise("iterations must be positive")
warmup = min(100, max(1, div(iterations, 10)))
payload = :binary.copy(<<0x5A>>, 32)

measure = fn operation ->
  for _ <- 1..iterations do
    started = System.monotonic_time(:nanosecond)
    operation.()
    System.monotonic_time(:nanosecond) - started
  end
end

stats = fn samples ->
  sorted = Enum.sort(samples)
  median = Enum.at(sorted, div(length(sorted), 2))
  p95 = Enum.at(sorted, max(0, ceil(length(sorted) * 0.95) - 1))
  {median, p95}
end

port = Port.open({:spawn_executable, String.to_charlist(port_echo_bin)}, [
  :binary,
  {:packet, 4},
  :exit_status
])
port_round_trip = fn ->
  true = Port.command(port, payload)

  receive do
    {^port, {:data, ^payload}} -> :ok
  after
    3_000 -> raise("Port echo timeout")
  end
end
Enum.each(1..warmup, fn _ -> port_round_trip.() end)
port_samples = measure.(port_round_trip)
Port.close(port)

short_name = "zbeam_bench_#{System.pid()}"
total_messages = warmup + iterations
zbeam_port = Port.open({:spawn_executable, String.to_charlist(zbeam_bin)}, [
  :binary,
  :exit_status,
  :stderr_to_stdout,
  args: ["echo", short_name, "zbeam_bench_cookie", Integer.to_string(total_messages)]
])

peer = String.to_atom("#{short_name}@127.0.0.1")
connected = Enum.any?(1..60, fn _ ->
  if Node.connect(peer) do
    true
  else
    Process.sleep(50)
    false
  end
end)
if !connected, do: raise("zbeam connection timeout")
zbeam_round_trip = fn ->
  send({:echo, peer}, payload)

  receive do
    ^payload -> :ok
  after
    3_000 -> raise("zbeam echo timeout")
  end
end
Enum.each(1..warmup, fn _ -> zbeam_round_trip.() end)
zbeam_samples = measure.(zbeam_round_trip)

receive do
  {^zbeam_port, {:exit_status, 0}} -> :ok
  {^zbeam_port, {:exit_status, status}} -> raise("zbeam exit status #{status}")
after
  3_000 -> raise("zbeam exit timeout")
end

{port_median, port_p95} = stats.(port_samples)
{zbeam_median, zbeam_p95} = stats.(zbeam_samples)
IO.puts("implementation\titerations\tpayload_bytes\tmedian_ns\tp95_ns")
IO.puts("erlang_port\t#{iterations}\t#{byte_size(payload)}\t#{port_median}\t#{port_p95}")
IO.puts("zbeam_distribution\t#{iterations}\t#{byte_size(payload)}\t#{zbeam_median}\t#{zbeam_p95}")
