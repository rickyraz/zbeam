defmodule ZbeamResearch.ComparisonTest do
  use ExUnit.Case
  alias ZbeamResearch.Comparison, as: C

  test "all NIF adapters use the requested job and reject mismatches" do
    for label <- ["zigler_sync", "zigler_dirty_cpu", "zigler_threaded"] do
      assert C.call(C.start(label, "echo", 1), "abc") == "abc"
      assert C.call(C.start(label, "sha256", 1), "abc") == :crypto.hash(:sha256, "abc")
    end

    assert_raise RuntimeError, fn -> C.check("bad", "abc") end
    assert_raise RuntimeError, fn -> C.start("missing", "echo", 1) end
  end
end
