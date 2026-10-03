defmodule ZbeamResearch.NativeTest do
  use ExUnit.Case
  alias ZbeamResearch.Native

  test "all scheduling modes return exact bounded binary results" do
    for input <- [<<>>, "abc", :binary.copy(<<90>>, 65_536)] do
      for fun <- [:echo, :echo_dirty, :echo_threaded],
          do: assert(apply(Native, fun, [input]) == input)

      for fun <- [:hash, :hash_dirty, :hash_threaded],
          do: assert(apply(Native, fun, [input]) == :crypto.hash(:sha256, input))
    end

    for fun <- [:echo, :echo_dirty, :echo_threaded, :hash, :hash_dirty, :hash_threaded] do
      assert_raise ErlangError, fn -> apply(Native, fun, [:binary.copy(<<0>>, 1_048_577)]) end
    end
  end
end
