defmodule ResearchPeer do
  def start(bin, pause_ms, fault \\ "none", epmd_port \\ 4369) do
    name = "lab_#{System.pid()}_#{System.unique_integer([:positive])}"
    port = Port.open({:spawn_executable, String.to_charlist(Path.expand(bin))},
      [:binary, :exit_status, :stderr_to_stdout,
       args: [name, Atom.to_string(Node.get_cookie()), to_string(pause_ms), fault, to_string(epmd_port)]])
    peer = String.to_atom("#{name}@127.0.0.1")
    try do
      ready(port, "READY", 5_000)
      true = Node.connect(peer)
      true = Node.monitor(peer, true)
      {port, peer}
    rescue
      exception -> stop({port, peer}); reraise exception, __STACKTRACE__
    end
  end
  def ready(port, marker, timeout), do: ready(port, marker, System.monotonic_time(:millisecond) + timeout, "")
  defp ready(port, marker, deadline, collected) do
    remaining = max(0, deadline - System.monotonic_time(:millisecond))
    receive do
      {^port, {:data, text}} ->
        text = collected <> text
        if byte_size(text) > 32_768, do: raise("excessive child diagnostics")
        if !String.contains?(text, marker), do: ready(port, marker, deadline, text)
      {^port, {:exit_status, status}} -> raise "child exited #{status} before #{marker}"
    after
      remaining -> raise "child marker timeout: #{marker}"
    end
  end
  def request(peer, input, timeout \\ 5000) do
    send({:sha256, peer}, input)
    expected = :crypto.hash(:sha256, input)
    receive do
      ^expected -> :ok
      {:nodedown, ^peer} -> {:error, :nodedown}
    after
      timeout -> {:error, :timeout}
    end
  end
  def stop({port, peer}) do
    if peer, do: Node.monitor(peer, false)
    if info = Port.info(port) do
      System.cmd("kill", ["-KILL", to_string(Keyword.fetch!(info, :os_pid))], stderr_to_stdout: true)
      if Port.info(port), do: Port.close(port)
    end
    :ok
  end
  def snapshot(sender, sent) do
    queues = for {node, controller} <- :erlang.system_info(:dist_ctrl) do
      queue = if is_port(controller), do: inspect(Port.info(controller, :queue_size)), else: "unavailable: PID controller"
      %{node: to_string(node), queue: queue}
    end
    %{sent: :atomics.get(sent, 1), beam_bytes: :erlang.memory(:total),
      sender: inspect(Process.info(sender, [:status, :message_queue_len, :memory])), distribution: queues}
  end
end
