Code.require_file("../../examples/two_worker_owner.ex", __DIR__)
Code.require_file("m2c_test_support.exs", __DIR__)
ExUnit.start(trace: true)

defmodule TwoWorkerProcessTest do
  use ExUnit.Case, async: false
  import M2cTestSupport
  @root Path.expand("../..", __DIR__)
  @name :m2c_process_owner
  @peer String.to_atom("m2c_process_#{System.pid()}@127.0.0.1")
  @bin System.argv() |> hd() |> Path.expand()

  defp kill(pid, signal) do
    {_, 0} = System.cmd("kill", ["-#{signal}", to_string(pid)], stderr_to_stdout: true)
  end

  defp start do
    Process.flag(:trap_exit, true)
    opts = [name: @name, peer: @peer, executable: @bin]

    {:ok, sup} =
      Supervisor.start_link([{TwoWorkerOwner, opts}],
        strategy: :one_for_one,
        max_restarts: 2,
        max_seconds: 5
      )

    Process.unlink(sup)
    on_exit(fn -> if Process.alive?(sup), do: Supervisor.stop(sup) end)
    sup
  end

  defp current do
    owner = Process.whereis(@name)
    state = :sys.get_state(owner)
    {guard, native} = child_pids(state.port)
    {owner, state, guard, native}
  end

  defp replacement(old) do
    await(fn -> is_pid(Process.whereis(@name)) and Process.whereis(@name) != old end)
    current()
  end

  test "terminal PIDs are not probed again while other children exit" do
    counts = :atomics.new(2, [])

    probe = fn
      :terminal ->
        :atomics.add_get(counts, 1, 1)
        false

      :closing ->
        :atomics.add_get(counts, 2, 1) == 1
    end

    assert :ok = await_dead([:terminal, :closing], 1_000, probe)
    assert :atomics.get(counts, 1) == 1
    assert :atomics.get(counts, 2) == 2
  end

  for victim <- [:guardian, :native] do
    @victim victim
    test "owned #{@victim} kill fences two requests and restarts" do
      sup = start()
      {owner, state, guard, native} = current()
      kill(native, "STOP")
      a = Task.async(fn -> TwoWorkerOwner.hash(@name, :a, "uncertain a") end)
      b = Task.async(fn -> TwoWorkerOwner.hash(@name, :b, "uncertain b") end)
      await(fn -> map_size(:sys.get_state(owner).pending) == 2 end)
      kill(if(@victim == :guardian, do: guard, else: native), "KILL")
      assert Task.await(a, 2_000) == {:error, :worker_lost}
      assert Task.await(b, 2_000) == {:error, :worker_lost}
      {_, fresh, fresh_guard, fresh_native} = replacement(owner)
      assert elem(fresh.actors.a, 0) != elem(state.actors.a, 0)
      assert elem(fresh.actors.b, 0) != elem(state.actors.b, 0)
      await_dead([guard, native])
      assert TwoWorkerOwner.hash(@name, :a, "fresh") == {:ok, :crypto.hash(:sha256, "fresh")}
      Supervisor.stop(sup)
      await_dead([fresh_guard, fresh_native])
    end
  end

  test "restart intensity stops a crash loop and cleans each owned child" do
    sup = start()
    monitor = Process.monitor(sup)
    {first, _, first_guard, first_native} = current()
    kill(first_native, "KILL")
    {second, _, second_guard, second_native} = replacement(first)
    await_dead([first_guard, first_native])
    kill(second_native, "KILL")
    {third, _, third_guard, third_native} = replacement(second)
    await_dead([second_guard, second_native])
    assert Process.alive?(third)
    kill(third_native, "KILL")
    assert_receive {:DOWN, ^monitor, :process, ^sup, :shutdown}, 5_000
    await_dead([third_guard, third_native])
    assert Process.whereis(@name) == nil
  end

  test "BEAM VM kill closes both guardian levels and the stopped native child" do
    Process.flag(:trap_exit, true)

    path =
      Path.join(
        System.tmp_dir!(),
        "zbeam-m2c-vm-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    node = "m2c_vm_#{System.pid()}_#{System.unique_integer([:positive])}@127.0.0.1"

    port =
      Port.open({:spawn_executable, System.find_executable("python3")}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: [
          @root <> "/examples/worker_guard.py",
          System.find_executable("elixir"),
          "--erl",
          "+S 2:2",
          "--name",
          node,
          "--cookie",
          Atom.to_string(Node.get_cookie()),
          @root <> "/tests/interop/two_worker_owner_vm_crash.exs",
          @bin,
          path
        ]
      ])

    on_exit(fn ->
      if Port.info(port) != nil, do: TwoWorkerLaunch.close(port)
      File.rm(path)
      File.rm(path <> ".tmp")
    end)

    {outer_guard, vm} = child_pids(port)
    await(fn -> File.exists?(path) end)

    [reported_vm, inner_guard, native] =
      File.read!(path) |> String.split() |> Enum.map(&String.to_integer/1)

    assert reported_vm == vm
    assert live?(inner_guard) and live?(native)
    kill(vm, "KILL")
    await_dead([outer_guard, vm, inner_guard, native])
  end
end
