Code.require_file("../../examples/two_worker_admission.ex", __DIR__)
ExUnit.start(trace: true)

defmodule TwoWorkerAdmissionTest do
  use ExUnit.Case, async: false
  @name :m2c_admission_test

  defp owner do
    parent = self()

    {pid, monitor} =
      spawn_monitor(fn ->
        Process.register(self(), @name)
        :ets.new(@name, [:named_table, :public, :set])
        send(parent, {:ready, self(), :ets.whereis(@name)})

        receive do
          :stop -> :ok
        end
      end)

    assert_receive {:ready, ^pid, table}, 1_000

    on_exit(fn ->
      ref = Process.monitor(pid)
      if Process.alive?(pid), do: send(pid, :stop)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1_000
    end)

    {pid, monitor, table}
  end

  test "validates before claiming and keeps one slot per actor" do
    {pid, _, table} = owner()
    assert TwoWorkerAdmission.claim(@name, :c, <<>>) == {:error, :invalid_input}
    assert TwoWorkerAdmission.claim(@name, :a, :not_binary) == {:error, :invalid_input}

    assert TwoWorkerAdmission.claim(@name, :a, :binary.copy(<<0>>, 1_048_577)) ==
             {:error, :invalid_input}

    assert :ets.info(table, :size) == 0
    assert {:ok, ^pid, ^table, a} = TwoWorkerAdmission.claim(@name, :a, <<>>)

    assert {:ok, ^pid, ^table, b} =
             TwoWorkerAdmission.claim(@name, :b, :binary.copy(<<0>>, 1_048_576))

    assert TwoWorkerAdmission.claim(@name, :a, <<>>) == {:error, :busy}
    assert TwoWorkerAdmission.claim(@name, :b, <<>>) == {:error, :busy}
    assert TwoWorkerAdmission.matches?(table, :a, self(), a)
    TwoWorkerAdmission.release(table, :a, self(), make_ref())
    assert TwoWorkerAdmission.matches?(table, :a, self(), a)
    TwoWorkerAdmission.release(table, :a, self(), a)
    TwoWorkerAdmission.release(table, :b, self(), b)
    assert :ets.info(table, :size) == 0
  end

  test "table not owned by the registered process cannot admit" do
    table = :ets.new(@name, [:named_table, :public, :set])
    assert TwoWorkerAdmission.claim(@name, :a, <<1>>) == {:error, :not_ready}
    assert :ets.info(table, :size) == 0
  end

  test "concurrent callers cannot exceed one claim per actor" do
    {owner, _, table} = owner()
    parent = self()

    callers =
      for actor <- [:a, :b], _ <- 1..40 do
        spawn(fn ->
          result = TwoWorkerAdmission.claim(@name, actor, <<1>>)
          send(parent, {:claim, self(), actor, result})

          receive do
            :stop -> :ok
          end
        end)
      end

    try do
      results =
        for _ <- callers do
          assert_receive {:claim, caller, actor, result}, 2_000
          {caller, actor, result}
        end

      for actor <- [:a, :b] do
        accepted =
          for {caller, ^actor, {:ok, ^owner, ^table, ticket}} <- results, do: {caller, ticket}

        assert length(accepted) == 1
        assert Enum.count(results, fn {_, a, r} -> a == actor and r == {:error, :busy} end) == 39
        [{caller, ticket}] = accepted
        assert TwoWorkerAdmission.matches?(table, actor, caller, ticket)
      end

      assert :ets.info(table, :size) == 2
    after
      Enum.each(callers, &send(&1, :stop))
    end
  end

  test "dead caller is detectable before delivery and owner death removes its slots" do
    {pid, monitor, table} = owner()
    parent = self()

    {caller, caller_monitor} =
      spawn_monitor(fn ->
        send(parent, {:claimed, TwoWorkerAdmission.claim(@name, :a, <<1>>)})
      end)

    assert_receive {:claimed, {:ok, ^pid, ^table, ticket}}, 1_000
    assert_receive {:DOWN, ^caller_monitor, :process, ^caller, :normal}, 1_000
    assert TwoWorkerAdmission.matches?(table, :a, caller, ticket)
    assert TwoWorkerAdmission.abandoned?(table)
    send(pid, :stop)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}, 1_000
    assert TwoWorkerAdmission.claim(@name, :a, <<>>) == {:error, :not_ready}

    {replacement, _, next_table} = owner()
    assert next_table != table and replacement != pid
    assert {:ok, ^replacement, ^next_table, _} = TwoWorkerAdmission.claim(@name, :a, <<>>)
  end
end
