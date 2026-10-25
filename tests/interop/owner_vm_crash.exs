Code.require_file("../../examples/native_worker_owner.ex", __DIR__)
[bin, path] = System.argv()
root = Path.expand("../..", __DIR__)

launch = fn ->
  name = "owned_#{System.pid()}"

  port =
    Port.open(
      {:spawn_executable, System.find_executable("python3")},
      [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: [
          root <> "/examples/worker_guard.py",
          bin,
          "serve-worker",
          name,
          Atom.to_string(Node.get_cookie())
        ]
      ]
    )

  {port, String.to_atom(name <> "@127.0.0.1")}
end

{:ok, owner} = NativeWorkerOwner.start_link(name: :crash_owner, launch: launch)
state = :sys.get_state(owner)
{:os_pid, guard} = Port.info(state.port, :os_pid)
[native] = File.read!("/proc/#{guard}/task/#{guard}/children") |> String.split()
File.write!(path, "#{System.pid()} #{guard} #{native}\n")
Process.sleep(:infinity)
