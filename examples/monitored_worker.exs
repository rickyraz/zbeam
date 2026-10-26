Code.require_file("native_worker_owner.ex", __DIR__)
[bin] = System.argv()
true = File.regular?(bin)
true = Node.alive?()
python = System.find_executable("python3") || raise "Python 3 is required"

launch = fn ->
  short = "example_#{System.pid()}_#{System.unique_integer([:positive])}"

  port =
    Port.open({:spawn_executable, python}, [
      :binary,
      :exit_status,
      :stderr_to_stdout,
      args: [
        Path.join(__DIR__, "worker_guard.py"),
        Path.expand(bin),
        "serve-worker",
        short,
        Atom.to_string(Node.get_cookie())
      ]
    ])

  {port, String.to_atom(short <> "@127.0.0.1")}
end

{:ok, supervisor} =
  Supervisor.start_link(
    [
      {NativeWorkerOwner, [name: :native_example, launch: launch, timeout_ms: 1_000]}
    ], strategy: :one_for_one, max_restarts: 3, max_seconds: 5)

try do
  for input <- ["hello", "native worker", "owned copies"] do
    expected = :crypto.hash(:sha256, input)
    {:ok, ^expected} = NativeWorkerOwner.hash(:native_example, input)
    IO.puts("verified SHA-256: " <> input)
  end

  IO.puts("PASS monitored native worker example")
after
  Supervisor.stop(supervisor)
end
