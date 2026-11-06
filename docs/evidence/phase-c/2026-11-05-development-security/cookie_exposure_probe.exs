# Historical exposure probe: run only with the explicitly public cookie below.
root = Path.expand("../../../..", __DIR__)
Code.require_file(Path.join(root, "examples/two_worker_launch.ex"))
Code.require_file(Path.join(root, "tests/interop/m2c_test_support.exs"))

defmodule CookieExposureProbe do
  import M2cTestSupport

  def run(executable) do
    true = Node.get_cookie() == :zbeam_public_probe_cookie
    Process.flag(:trap_exit, true)
    peer = String.to_atom("cookie_probe_#{System.pid()}@127.0.0.1")
    {:ok, port} = TwoWorkerLaunch.start(peer, Path.expand(executable), 3_000)
    {guard, native} = child_pids(port)

    try do
      present = fn pid ->
        {:ok, cmdline} = File.read("/proc/#{pid}/cmdline")
        Atom.to_string(Node.get_cookie()) in String.split(cmdline, <<0>>, trim: true)
      end

      true = present.(guard)
      true = present.(native)
      IO.puts("PASS public test-cookie appears in both owned guard and native argv")
    after
      TwoWorkerLaunch.close(port)
      await_dead([guard, native])
    end
  end
end

[executable] = System.argv()
CookieExposureProbe.run(executable)
