defmodule TwoWorkerAdmission do
  @moduledoc false

  # The returned owner and table refer to the same lifetime, even across restart.
  def claim(name, actor, input)
      when is_atom(name) and actor in [:a, :b] and is_binary(input) and
             byte_size(input) <= 1_048_576 do
    table = :ets.whereis(name)
    owner = :ets.info(table, :owner)
    ticket = make_ref()

    cond do
      not is_pid(owner) or Process.whereis(name) != owner -> {:error, :not_ready}
      :ets.insert_new(table, {actor, self(), ticket}) -> {:ok, owner, table, ticket}
      true -> {:error, :busy}
    end
  rescue
    ArgumentError -> {:error, :not_ready}
  end

  def claim(_, _, _), do: {:error, :invalid_input}

  def matches?(table, actor, caller, ticket),
    do: :ets.lookup(table, actor) == [{actor, caller, ticket}]

  def release(table, actor, caller, ticket),
    do: :ets.delete_object(table, {actor, caller, ticket})

  def abandoned?(table),
    do: Enum.any?(:ets.tab2list(table), fn {_, caller, _} -> not Process.alive?(caller) end)
end
