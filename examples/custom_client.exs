Code.require_file("two_worker_launch.ex", __DIR__)
Code.require_file("two_worker_peer.ex", __DIR__)

defmodule CustomClientExample do
  def run(executable) do
    Process.flag(:trap_exit, true)
    peer = String.to_atom("custom_example_#{System.pid()}@127.0.0.1")
    {:ok, port} = TwoWorkerLaunch.start(peer, Path.expand(executable), 3_000, "serve-custom")

    try do
      deadline = System.monotonic_time(:millisecond) + 3_000
      {:ok, actors} = TwoWorkerPeer.connect(port, peer, deadline)
      {a, _} = actors.a
      {b, _} = actors.b
      {:ok, "HELLO"} = call(a, {:call, "hello"})
      {:ok, "WORLD"} = call(b, {:call, "world"})
      IO.puts("PASS compiled Zig uppercase handler on both workers")
    after
      Node.monitor(peer, false)
      Node.disconnect(peer)
      TwoWorkerLaunch.close(port)
    end
  end

  defp call(pid, command) do
    ref = make_ref()
    :ok = :erlang.send(pid, {self(), ref, command}, [:noconnect, :nosuspend])

    receive do
      {^ref, result} -> result
    after
      3_000 -> raise "custom worker response timed out"
    end
  end
end

[executable] = System.argv()
CustomClientExample.run(executable)
