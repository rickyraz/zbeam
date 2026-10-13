Code.require_file("research_support.exs", __DIR__)
[bin] = System.argv()
for mode <- ["oom", "panic", "spin"] do
  context = {port, peer} = ResearchPeer.start(bin, 50, mode)
  try do
    send({:sha256, peer}, "abc")
    ResearchPeer.ready(port, "PAUSED", 5000)
    if mode == "spin" do
      receive do
        reply when is_binary(reply) -> raise "spin unexpectedly replied: #{inspect(reply)}"
      after
        200 -> :ok
      end
      true = Port.info(port) != nil
    else
      receive do
        {:nodedown, ^peer} -> :ok
      after
        3000 -> raise "fault did not disconnect"
      end
      receive do
        {^port, {:exit_status, status}} when status != 0 -> :ok
      after
        3000 -> raise "fault did not fail-stop"
      end
    end
    IO.puts("PASS test-owned fault #{mode}; controlling BEAM alive")
  after
    ResearchPeer.stop(context)
  end
end
