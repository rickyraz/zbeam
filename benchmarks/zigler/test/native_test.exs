defmodule ZbeamResearch.NativeTest do
  use ExUnit.Case
  alias ZbeamResearch.Native

  @tag :threaded_unverified
  test "threaded echo preserves terms across repeated thread-environment teardown" do
    for i <- 1..2000 do
      input = :binary.copy(<<rem(i, 251)>>, rem(i, 97))
      assert Native.echo_threaded(input) == input
    end
  end

  test "normal and dirty scheduling return exact bounded binary results" do
    for input <- [<<>>, "abc", :binary.copy(<<90>>, 65_536)] do
      for fun <- [:echo, :echo_dirty],
          do: assert(apply(Native, fun, [input]) == input)

      for fun <- [:hash, :hash_dirty],
          do: assert(apply(Native, fun, [input]) == :crypto.hash(:sha256, input))
    end

    for fun <- [:echo, :echo_dirty, :hash, :hash_dirty] do
      assert_raise ErlangError, fn -> apply(Native, fun, [:binary.copy(<<0>>, 1_048_577)]) end
    end
  end
end
