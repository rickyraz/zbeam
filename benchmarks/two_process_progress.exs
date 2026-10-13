Code.require_file("research_support.exs", __DIR__)
[bin] = System.argv()
for trial <- 1..10 do
  slow = {_slow_port, slow_peer} = ResearchPeer.start(bin, 1500)
  try do
    fast = {_fast_port, fast_peer} = ResearchPeer.start(bin, 0)
    try do
      pending = Task.async(fn -> ResearchPeer.request(slow_peer, "slow") end)
      Process.sleep(100)
      started = System.monotonic_time(:microsecond)
      for n <- 1..100 do
        :ok = ResearchPeer.request(fast_peer, "fast_#{n}")
      end
      elapsed = System.monotonic_time(:microsecond) - started
      true = elapsed < 1_000_000
      nil = Task.yield(pending, 0)
      :ok = Task.await(pending, 5000)
      IO.puts("RESULT " <> JSON.encode!(%{trial: trial, fast_100_requests_us: elapsed, slow_pause_ms: 1500,
        note: "two connections and two OS processes; progress control, not actor throughput equivalence"}))
    after
      ResearchPeer.stop(fast)
    end
  after
    ResearchPeer.stop(slow)
  end
end
