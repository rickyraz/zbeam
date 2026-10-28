defmodule M2cTestSupport do
  import ExUnit.Assertions

  def await(predicate, timeout \\ 5_000) do
    deadline = System.monotonic_time(:millisecond) + timeout

    loop = fn loop ->
      if predicate.() do
        :ok
      else
        assert System.monotonic_time(:millisecond) < deadline, "bounded wait expired"
        Process.sleep(10)
        loop.(loop)
      end
    end

    loop.(loop)
  end

  def live?(pid) do
    case File.read("/proc/#{pid}/stat") do
      {:ok, stat} ->
        [{index, _} | _] = Enum.reverse(:binary.matches(stat, ") "))
        binary_part(stat, index + 2, 1) not in ["Z", "X", "x"]

      {:error, reason} when reason in [:enoent, :esrch] ->
        false

      {:error, reason} ->
        raise "proc stat: #{inspect(reason)}"
    end
  end

  def child_pids(port) do
    {:os_pid, guard} = Port.info(port, :os_pid)
    path = "/proc/#{guard}/task/#{guard}/children"

    await(fn ->
      case File.read(path) do
        {:ok, data} -> String.trim(data) != ""
        _ -> false
      end
    end)

    [native] = File.read!(path) |> String.split() |> Enum.map(&String.to_integer/1)
    {guard, native}
  end
end
