defmodule TwoWorkerPeer do
  @moduledoc false

  # Caller owns the port and must disconnect this exclusive peer before closing it.
  def connect(port, peer, deadline) do
    result =
      with true <- connect_node(peer, remaining(deadline)),
           true <- Node.monitor(peer, true),
           {:ok, a} <- discover(port, peer, :a, deadline),
           {:ok, b} <- discover(port, peer, :b, deadline),
           true <- a != b do
        {:ok, %{a: {a, Process.monitor(a)}, b: {b, Process.monitor(b)}}}
      else
        _ -> {:error, :not_ready}
      end

    case result do
      {:error, _} ->
        Node.monitor(peer, false)
        Node.disconnect(peer)

      _ ->
        :ok
    end

    result
  end

  defp connect_node(peer, timeout) do
    task = Task.async(fn -> Node.connect(peer) end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, true} -> true
      _ -> false
    end
  end

  defp remaining(deadline), do: max(0, deadline - System.monotonic_time(:millisecond))

  defp discover(port, peer, actor, deadline) do
    ref = make_ref()

    case :erlang.send({:zbeam_workers, peer}, {self(), ref, {:discover, actor}}, [
           :noconnect,
           :nosuspend
         ]) do
      :ok ->
        receive do
          {^ref, {:ok, pid}} when is_pid(pid) and node(pid) == peer -> {:ok, pid}
          {^port, {:exit_status, _}} -> {:error, :worker_lost}
          {:EXIT, ^port, _} -> {:error, :worker_lost}
          {:nodedown, ^peer} -> {:error, :worker_lost}
        after
          remaining(deadline) -> {:error, :not_ready}
        end

      _ ->
        {:error, :worker_lost}
    end
  end
end
