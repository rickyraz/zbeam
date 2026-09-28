# Development-only: elixir --name hash_client@127.0.0.1 --cookie development_cookie \
#   examples/sha256_worker.exs ./zig-out/bin/zbeam /path/to/file
[zbeam_bin, input_path] = System.argv()
if !Node.alive?(), do: raise("start Elixir with --name and --cookie")
size = File.stat!(input_path).size
if size > 1_048_576, do: raise("example accepts at most 1 MiB")
input = File.read!(input_path)
expected = :crypto.hash(:sha256, input)
name = "sha_worker_#{System.pid()}"
port = Port.open({:spawn_executable, String.to_charlist(zbeam_bin)}, [
  :binary, :exit_status, :stderr_to_stdout,
  args: ["serve-sha256", name, Atom.to_string(Node.get_cookie())]
])
peer = String.to_atom("#{name}@127.0.0.1")

try do
  if !Enum.any?(1..300, fn _ ->
    if Node.connect(peer), do: true, else: (Process.sleep(10); false)
  end), do: raise("native worker did not register")

  true = Node.monitor(peer, true)
  send({:sha256, peer}, input)
  receive do
    ^expected -> IO.puts("SHA-256 verified: #{Base.encode16(expected, case: :lower)}")
    {:nodedown, ^peer} -> raise("native worker disconnected")
  after
    3_000 -> raise("native worker timed out")
  end
after
  if Port.info(port) != nil, do: Port.close(port)
end
