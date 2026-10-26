defmodule NativeWorkerOwner do
  @moduledoc "Linux development owner: one admitted hash, PID monitoring, no replay."
  use GenServer

  def start_link(options) do
    GenServer.start_link(__MODULE__, options,
      name: Keyword.fetch!(options, :name),
      timeout: Keyword.get(options, :start_timeout_ms, 3_000)
    )
  end

  # Only this API admits work. The owner releases the slot, including caller loss;
  # callers cannot reopen it while a timed-out/uncertain operation still runs.
  def hash(name, input)
      when is_atom(name) and is_binary(input) and byte_size(input) <= 1_048_576 do
    table = :ets.whereis(name)
    ticket = make_ref()

    if :ets.insert_new(table, {:request, self(), ticket}) do
      try do
        GenServer.call(name, {:hash, ticket, input}, :infinity)
      catch
        :exit, _ -> {:error, :worker_lost}
      end
    else
      {:error, :busy}
    end
  rescue
    ArgumentError -> {:error, :not_ready}
  end

  def hash(_, _), do: {:error, :invalid_input}

  @impl true
  def init(options) do
    Process.flag(:trap_exit, true)
    Process.sleep(Keyword.get(options, :restart_delay_ms, 100))
    table = :ets.new(Keyword.fetch!(options, :name), [:named_table, :public, :set])
    {port, peer} = Keyword.fetch!(options, :launch).()
    deadline = System.monotonic_time(:millisecond) + 2_000

    with :ok <- connect(peer, deadline),
         true <- Node.monitor(peer, true),
         {:ok, pid} <- discover(port, peer, deadline) do
      monitor = Process.monitor(pid)
      Process.send_after(self(), :check_admission, 100)

      {:ok,
       %{
         port: port,
         peer: peer,
         pid: pid,
         monitor: monitor,
         table: table,
         pending: nil,
         timeout: Keyword.get(options, :timeout_ms, 1_000)
       }}
    else
      _ -> {:stop, :not_ready}
    end
  end

  defp connect(peer, deadline) do
    cond do
      Node.connect(peer) ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        {:error, :not_ready}

      true ->
        Process.sleep(20)
        connect(peer, deadline)
    end
  end

  defp discover(port, peer, deadline) do
    ref = make_ref()
    :ok = :erlang.send({:zbeam_worker, peer}, {self(), ref, :discover}, [:noconnect, :nosuspend])

    receive do
      {^ref, {:ok, pid}} when is_pid(pid) and node(pid) == peer -> {:ok, pid}
      {^port, {:exit_status, _}} -> {:error, :worker_lost}
      {:EXIT, ^port, _} -> {:error, :worker_lost}
    after
      max(0, deadline - System.monotonic_time(:millisecond)) -> {:error, :not_ready}
    end
  end

  @impl true
  def handle_call({:hash, ticket, input}, {caller, _} = from, %{pending: nil} = state)
      when is_binary(input) and byte_size(input) <= 1_048_576 do
    if :ets.lookup(state.table, :request) == [{:request, caller, ticket}] do
      ref = make_ref()
      timer = Process.send_after(self(), {:request_timeout, ref}, state.timeout)
      caller_monitor = Process.monitor(caller)
      state = %{state | pending: {from, ticket, ref, timer, caller_monitor}}

      case :erlang.send(state.pid, {self(), ref, {:hash, input}}, [:noconnect, :nosuspend]) do
        :ok -> {:noreply, state}
        _ -> fail(state, :worker_lost)
      end
    else
      {:reply, {:error, :not_ready}, state}
    end
  end

  def handle_call(_, _, state), do: {:reply, {:error, :busy_or_invalid}, state}

  @impl true
  def handle_info({ref, {:ok, digest}}, %{pending: {from, ticket, ref, timer, monitor}} = state)
      when is_binary(digest) and byte_size(digest) == 32 do
    Process.cancel_timer(timer)
    Process.demonitor(monitor, [:flush])
    :ets.delete_object(state.table, {:request, elem(from, 0), ticket})
    GenServer.reply(from, {:ok, digest})
    {:noreply, %{state | pending: nil}}
  end

  def handle_info({:request_timeout, ref}, %{pending: {_, _, ref, _, _}} = state),
    do: fail(state, :timeout)

  def handle_info({:DOWN, ref, :process, pid, _}, %{monitor: ref, pid: pid} = state),
    do: fail(state, :worker_lost)

  def handle_info({:DOWN, ref, :process, _, _}, %{pending: {_, _, _, _, ref}} = state),
    do: fail(state, :caller_lost)

  def handle_info({:nodedown, peer}, %{peer: peer} = state), do: fail(state, :worker_lost)
  def handle_info({port, {:exit_status, _}}, %{port: port} = state), do: fail(state, :worker_lost)
  def handle_info({:EXIT, port, _}, %{port: port} = state), do: fail(state, :worker_lost)

  def handle_info(:check_admission, state) do
    abandoned =
      case :ets.lookup(state.table, :request) do
        [{:request, caller, _}] -> not Process.alive?(caller)
        [] -> false
      end

    if abandoned do
      fail(state, :caller_lost)
    else
      Process.send_after(self(), :check_admission, 100)
      {:noreply, state}
    end
  end

  def handle_info(_, state), do: {:noreply, state}

  defp fail(state, reason) do
    if state.pending do
      {from, _, _, timer, monitor} = state.pending
      Process.cancel_timer(timer)
      Process.demonitor(monitor, [:flush])
      GenServer.reply(from, {:error, reason})
    end

    {:stop, {:shutdown, reason}, %{state | pending: nil}}
  end

  @impl true
  def terminate(_, state) do
    Node.monitor(state.peer, false)
    Node.disconnect(state.peer)
    close_port(state.port)
    :ok
  end

  defp close_port(port) do
    Port.close(port)
  rescue
    error in ArgumentError ->
      # Exit can close the port between an info check and close.
      if Port.info(port) != nil, do: reraise(error, __STACKTRACE__)
  end
end
