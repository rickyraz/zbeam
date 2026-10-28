defmodule TwoWorkerLaunch do
  @moduledoc false
  @guard Path.join(__DIR__, "worker_guard.py")

  # The caller owns the returned Port and traps exits throughout its lifetime.
  def start(peer, executable, timeout_ms)
      when is_atom(peer) and is_binary(executable) and is_integer(timeout_ms) and timeout_ms > 0 do
    with true <- Node.alive?(),
         [short, "127.0.0.1"] <- String.split(Atom.to_string(peer), "@", parts: 2),
         true <- Regex.match?(~r/\A[a-zA-Z0-9_-]{1,64}\z/, short),
         true <- peer != Node.self() and peer not in Node.list(:connected),
         true <- File.regular?(executable),
         python when is_binary(python) <- System.find_executable("python3"),
         deadline = System.monotonic_time(:millisecond) + timeout_ms,
         :ok <- await_available(short, deadline) do
      port =
        Port.open({:spawn_executable, python}, [
          :binary,
          :exit_status,
          :stderr_to_stdout,
          {:line, 1024},
          args: [
            @guard,
            Path.expand(executable),
            "serve-workers",
            short,
            Atom.to_string(Node.get_cookie())
          ]
        ])

      case await_registration(port, Atom.to_string(peer), deadline) do
        :ok ->
          {:ok, port}

        error ->
          close(port)
          error
      end
    else
      {:error, _} = error -> error
      _ -> {:error, :not_ready}
    end
  rescue
    ArgumentError -> {:error, :not_ready}
  end

  def start(_, _, _), do: {:error, :not_ready}

  def close(port) do
    Port.close(port)
  rescue
    error in ArgumentError -> if Port.info(port) != nil, do: reraise(error, __STACKTRACE__)
  end

  defp await_available(short, deadline) do
    left = deadline - System.monotonic_time(:millisecond)

    if left <= 0 do
      {:error, :name_taken}
    else
      case epmd_lookup(short, deadline) do
        :available ->
          :ok

        :taken ->
          Process.sleep(min(20, left))
          await_available(short, deadline)

        :error ->
          {:error, :not_ready}
      end
    end
  end

  defp epmd_lookup(short, deadline) do
    timeout = max(0, deadline - System.monotonic_time(:millisecond))

    case :gen_tcp.connect(
           {127, 0, 0, 1},
           4369,
           [:binary, active: false, send_timeout: timeout],
           timeout
         ) do
      {:ok, socket} ->
        try do
          with :ok <- :gen_tcp.send(socket, <<byte_size(short) + 1::16, 122, short::binary>>),
               {:ok, <<119, status>>} <-
                 :gen_tcp.recv(socket, 2, max(0, deadline - System.monotonic_time(:millisecond))) do
            case status do
              0 -> :taken
              1 -> :available
              _ -> :error
            end
          else
            _ -> :error
          end
        after
          :gen_tcp.close(socket)
        end

      _ ->
        :error
    end
  end

  defp await_registration(port, peer, deadline) do
    left = max(0, deadline - System.monotonic_time(:millisecond))

    receive do
      {^port, {:data, {:eol, line}}} ->
        if String.starts_with?(line, "registered #{peer} on port "),
          do: :ok,
          else: await_registration(port, peer, deadline)

      {^port, {:data, _}} ->
        await_registration(port, peer, deadline)

      {^port, {:exit_status, _}} ->
        {:error, :not_ready}

      {:EXIT, ^port, _} ->
        {:error, :not_ready}
    after
      left -> {:error, :not_ready}
    end
  end
end
