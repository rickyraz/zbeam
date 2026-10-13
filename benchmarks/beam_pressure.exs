Code.require_file("research_support.exs", __DIR__)
[bin, pause_arg] = System.argv()
pause_ms = String.to_integer(pause_arg)
true = pause_ms in [500, 3500, 8000]
true = :net_kernel.set_net_ticktime(4, 0) in [:change_initiated, :unchanged]
old_monitor = :erlang.system_monitor(self(), [:busy_dist_port])
context = {port, peer} = ResearchPeer.start(bin, pause_ms)
parent = self()
sent = :atomics.new(1, [])
count = 4096
payload = :binary.copy(<<90>>, 65_536)
expected = :crypto.hash(:sha256, payload)
probe = spawn_link(fn ->
  loop = fn loop -> receive do {caller, ref} -> send(caller, ref); loop.(loop) end end
  loop.(loop)
end)
{sender, ref} = spawn_monitor(fn ->
  for _ <- 1..count do
    case :erlang.send({:sha256, peer}, payload, [:noconnect]) do
      :ok -> :atomics.add(sent, 1, 1)
      :noconnect -> exit(:peer_disconnected)
    end
  end
  for _ <- 1..count do
    receive do ^expected -> :ok after 20_000 -> exit(:reply_timeout) end
  end
  send(parent, :sender_completed)
end)
try do
  ResearchPeer.ready(port, "PAUSED", 5000)
  started = System.monotonic_time(:millisecond)
  samples = for _ <- 1..div(pause_ms + 1500, 100) do
    Process.sleep(100)
    ping = make_ref()
    before = System.monotonic_time(:microsecond)
    send(probe, {self(), ping})
    receive do ^ping -> :ok after 1000 -> raise "unrelated process stalled" end
    probe_us = System.monotonic_time(:microsecond) - before
    Map.merge(ResearchPeer.snapshot(sender, sent), %{at_ms: System.monotonic_time(:millisecond) - started, probe_us: probe_us})
  end
  true = hd(samples).sent < count
  down = receive do {:nodedown, ^peer} -> true after 0 -> false end
  if !down do
    receive do :sender_completed -> :ok after 20_000 -> raise "sender did not resume" end
    receive do {:DOWN, ^ref, :process, ^sender, :normal} -> :ok after 1000 -> raise "sender failed" end
  end
  if pause_ms == 500, do: false = down
  if pause_ms == 8000, do: true = down
  events = Stream.repeatedly(fn -> receive do {:monitor, _, :busy_dist_port, _} -> 1 after 0 -> 0 end end)
    |> Enum.take_while(&(&1 == 1)) |> length()
  IO.puts("RESULT " <> JSON.encode!(%{pause_ms: pause_ms, ticktime_s: 4, frames: count, payload_bytes: 65536,
    nodedown: down, busy_dist_events: events, samples: samples, otp: to_string(:erlang.system_info(:otp_release)),
    note: "bounded 4096-frame burst; reply mailbox growth after resume is included, not a steady-state memory guarantee"}))
  if down do
    Process.exit(sender, :kill)
    Process.demonitor(ref, [:flush])
    true = Enum.any?(1..500, fn _ -> if Node.connect(peer), do: true, else: (Process.sleep(10); false) end)
    true = Node.monitor(peer, true)
    :ok = ResearchPeer.request(peer, "reconnected")
  end
  IO.puts("PASS OTP pressure, unrelated process progress and recovery")
after
  Process.exit(sender, :kill)
  Process.demonitor(ref, [:flush])
  Process.unlink(probe)
  Process.exit(probe, :kill)
  ResearchPeer.stop(context)
  case old_monitor do
    :undefined -> :erlang.system_monitor(:undefined)
    {pid, options} -> :erlang.system_monitor(pid, options)
  end
end
