defmodule ZbeamResearch.BatchTest do
  use ExUnit.Case

  test "dirty batch hashes independent jobs including empty input and exact limit" do
    for count <- [1, 8, 32], size <- [0, 32, 4096, 32768], size * count <= 1_048_576 do
      jobs = for n <- 1..count, do: :binary.copy(<<n>>, size)
      expected = jobs |> Enum.map(&:crypto.hash(:sha256, &1)) |> IO.iodata_to_binary()
      assert expected == ZbeamResearch.BatchNative.hash_batch(IO.iodata_to_binary(jobs), count)
    end
  end

  test "dirty batch refuses excessive count, bytes or unequal packed jobs" do
    for {input, count} <- [{"", 0}, {"", 33}, {"abc", 2}, {:binary.copy(<<0>>, 1_048_577), 1}] do
      assert_raise ErlangError, fn -> ZbeamResearch.BatchNative.hash_batch(input, count) end
    end
  end
end
