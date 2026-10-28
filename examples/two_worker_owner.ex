Code.require_file("two_worker_admission.ex", __DIR__)
Code.require_file("two_worker_launch.ex", __DIR__)
Code.require_file("two_worker_peer.ex", __DIR__)

defmodule TwoWorkerOwner do
  @moduledoc "Linux development owner for two fixed workers; uncertain work is never replayed."
  use GenServer

  def start_link(options) do
    GenServer.start_link(__MODULE__, options,
      name: Keyword.fetch!(options, :name),
      timeout: Keyword.get(options, :start_timeout_ms, 5_000)
    )
  end

  def hash(name, actor, input) do
    case TwoWorkerAdmission.claim(name, actor, input) do
      {:ok, owner, _, ticket} ->
        try do
          GenServer.call(owner, {:hash, actor, ticket, input}, :infinity)
        catch
          :exit, _ -> {:error, :worker_lost}
        end

      error ->
        error
    end
  end

  @impl true
  def init(options) do
    Process.flag(:trap_exit, true)
    name = Keyword.fetch!(options, :name)
    peer = Keyword.fetch!(options, :peer)
    executable = Keyword.fetch!(options, :executable)
    timeout = Keyword.get(options, :timeout_ms, 1_000)
    startup = Keyword.get(options, :startup_ms, 3_000)

    with true <- is_integer(timeout) and timeout > 0 and is_integer(startup) and startup > 0,
         deadline = System.monotonic_time(:millisecond) + startup,
         {:ok, port} <- TwoWorkerLaunch.start(peer, executable, startup) do
      result =
        try do
          initialize(name, peer, port, timeout, deadline)
        catch
          kind, reason ->
            cleanup(peer, port)
            :erlang.raise(kind, reason, __STACKTRACE__)
        end

      case result do
        {:ok, state} ->
          {:ok, state}

        {:error, reason} ->
          cleanup(peer, port)
          {:stop, reason}
      end
    else
      _ -> {:stop, :not_ready}
    end
  end

  defp initialize(name, peer, port, timeout, deadline) do
    with {:ok, actors} <- TwoWorkerPeer.connect(port, peer, deadline) do
      :ets.new(name, [:named_table, :public, :set])
      table = :ets.whereis(name)
      Process.send_after(self(), :check_admission, 100)

      {:ok,
       %{peer: peer, port: port, actors: actors, table: table, pending: %{}, timeout: timeout}}
    end
  rescue
    ArgumentError -> {:error, :not_ready}
  end

  defp cleanup(peer, port) do
    Node.monitor(peer, false)
    Node.disconnect(peer)
    TwoWorkerLaunch.close(port)
  end

  @impl true
  def handle_call({:hash, actor, ticket, input}, {caller, _} = from, state)
      when actor in [:a, :b] and is_binary(input) and byte_size(input) <= 1_048_576 do
    cond do
      not TwoWorkerAdmission.matches?(state.table, actor, caller, ticket) ->
        {:reply, {:error, :not_ready}, state}

      state.actors[actor] == nil ->
        TwoWorkerAdmission.release(state.table, actor, caller, ticket)
        {:reply, {:error, :unavailable}, state}

      Map.has_key?(state.pending, actor) ->
        {:reply, {:error, :busy}, state}

      true ->
        {pid, _} = state.actors[actor]
        ref = make_ref()
        timer = Process.send_after(self(), {:request_timeout, actor, ref}, state.timeout)
        monitor = Process.monitor(caller)
        pending = Map.put(state.pending, actor, {from, ticket, ref, timer, monitor})
        state = %{state | pending: pending}

        case :erlang.send(pid, {self(), ref, {:hash, input}}, [:noconnect, :nosuspend]) do
          :ok -> {:noreply, state}
          _ -> fail(state, :worker_lost)
        end
    end
  end

  def handle_call(_, _, state), do: {:reply, {:error, :invalid_input}, state}

  @impl true
  def handle_info({ref, {:ok, digest}}, state)
      when is_reference(ref) and is_binary(digest) and byte_size(digest) == 32 do
    case actor_for_ref(state, ref) do
      nil -> {:noreply, state}
      actor -> {:noreply, finish(state, actor, {:ok, digest})}
    end
  end

  def handle_info({ref, {:error, reason}}, state)
      when is_reference(ref) and reason in [:stopped, :canceled, :handler_failed, :bad_request] do
    case actor_for_ref(state, ref) do
      nil ->
        {:noreply, state}

      actor ->
        state = finish(state, actor, {:error, reason})

        state =
          if reason in [:stopped, :canceled, :handler_failed],
            do: retire(state, actor),
            else: state

        {:noreply, state}
    end
  end

  def handle_info({:request_timeout, actor, ref}, state) do
    if actor_for_ref(state, ref) == actor,
      do: fail(state, {:timeout, actor}),
      else: {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    actor = Enum.find([:a, :b], fn a -> state.actors[a] == {pid, ref} end)
    caller = Enum.find(state.pending, fn {_, {_, _, _, _, monitor}} -> monitor == ref end)

    cond do
      actor && reason == :noconnection -> fail(state, :worker_lost)
      actor -> {:noreply, state |> finish(actor, {:error, :worker_lost}) |> retire(actor)}
      caller -> fail(state, :caller_lost)
      true -> {:noreply, state}
    end
  end

  def handle_info({:nodedown, peer}, %{peer: peer} = state), do: fail(state, :worker_lost)
  def handle_info({port, {:exit_status, _}}, %{port: port} = state), do: fail(state, :worker_lost)
  def handle_info({:EXIT, port, _}, %{port: port} = state), do: fail(state, :worker_lost)

  def handle_info(:check_admission, state) do
    if TwoWorkerAdmission.abandoned?(state.table) do
      fail(state, :caller_lost)
    else
      Process.send_after(self(), :check_admission, 100)
      {:noreply, state}
    end
  end

  def handle_info(_, state), do: {:noreply, state}

  defp actor_for_ref(state, ref) do
    Enum.find_value(state.pending, fn {actor, {_, _, pending_ref, _, _}} ->
      if ref == pending_ref, do: actor
    end)
  end

  defp finish(state, actor, reply) do
    case Map.pop(state.pending, actor) do
      {nil, _} ->
        state

      {{from, ticket, _, timer, monitor}, pending} ->
        Process.cancel_timer(timer)
        Process.demonitor(monitor, [:flush])
        TwoWorkerAdmission.release(state.table, actor, elem(from, 0), ticket)
        GenServer.reply(from, reply)
        %{state | pending: pending}
    end
  end

  defp retire(state, actor) do
    case state.actors[actor] do
      {_, monitor} -> Process.demonitor(monitor, [:flush])
      nil -> :ok
    end

    %{state | actors: Map.put(state.actors, actor, nil)}
  end

  defp fail(state, reason) do
    for {actor, {from, _, _, timer, monitor}} <- state.pending do
      Process.cancel_timer(timer)
      Process.demonitor(monitor, [:flush])
      reply = if reason == {:timeout, actor}, do: {:error, :timeout}, else: {:error, :worker_lost}
      GenServer.reply(from, reply)
    end

    {:stop, {:shutdown, reason}, %{state | pending: %{}}}
  end

  @impl true
  def terminate(_, state) do
    cleanup(state.peer, state.port)
    :ok
  end
end
