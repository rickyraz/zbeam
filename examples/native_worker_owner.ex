defmodule NativeWorkerOwner do
  @moduledoc "Development owner: one outstanding hash, external restart, no replay."
  use GenServer
  def start_link(options), do: GenServer.start_link(__MODULE__, options, name: Keyword.fetch!(options, :name))

  @impl true
  def init(options) do
    Process.flag(:trap_exit, true)
    Process.sleep(Keyword.get(options, :restart_delay_ms, 100))
    {port, peer} = Keyword.fetch!(options, :launch).()
    if peer, do: true = Node.monitor(peer, true)
    {:ok, %{port: port, peer: peer, pending: nil, timeout: Keyword.get(options, :timeout_ms, 1000)}}
  end

  @impl true
  def handle_call({:hash, input}, from, %{pending: nil} = state) when is_binary(input) and byte_size(input) <= 1_048_576 do
    ref = make_ref()
    timer = Process.send_after(self(), {:request_timeout, ref}, state.timeout)
    state = %{state | pending: {from, ref, timer}}
    sent = try do
      if state.peer do
        :erlang.send({:sha256, state.peer}, input, [:noconnect, :nosuspend])
      else
        if Port.command(state.port, input, [:nosuspend]), do: :ok, else: :nosuspend
      end
    rescue
      ArgumentError -> :worker_lost
    end
    case sent do
      :ok -> {:noreply, state}
      _ -> fail(state, :worker_lost)
    end
  end
  def handle_call({:hash, _}, _from, state), do: {:reply, {:error, :busy_or_invalid}, state}

  @impl true
  def handle_info(reply, %{pending: {from, _, timer}} = state) when is_binary(reply) and byte_size(reply) == 32 do
    Process.cancel_timer(timer)
    GenServer.reply(from, {:ok, reply})
    {:noreply, %{state | pending: nil}}
  end
  def handle_info({port, {:data, reply}}, %{port: port, peer: nil} = state), do: handle_info(reply, state)
  def handle_info({:request_timeout, ref}, %{pending: {_, ref, _}} = state), do: fail(state, :timeout)
  def handle_info({:nodedown, peer}, %{peer: peer} = state), do: fail(state, :worker_lost)
  def handle_info({port, {:exit_status, _}}, %{port: port} = state), do: fail(state, :worker_lost)
  def handle_info({:EXIT, port, _}, %{port: port} = state), do: fail(state, :worker_lost)
  def handle_info(_, state), do: {:noreply, state}

  defp fail(state, reason) do
    if state.pending do
      {from, _, timer} = state.pending
      Process.cancel_timer(timer)
      GenServer.reply(from, {:error, reason})
    end
    # Restart the connection on timeout so an uncorrelated late reply cannot match a later request.
    {:stop, {:shutdown, reason}, %{state | pending: nil}}
  end

  @impl true
  def terminate(_, state) do
    if state.peer, do: Node.monitor(state.peer, false)
    if info = Port.info(state.port) do
      System.cmd("kill", ["-KILL", to_string(Keyword.fetch!(info, :os_pid))], stderr_to_stdout: true)
      if Port.info(state.port), do: Port.close(state.port)
    end
    :ok
  end
end
