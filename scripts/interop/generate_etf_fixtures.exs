# OTP itself is the oracle: generating with :erlang.term_to_binary/1 avoids
# copying zbeam's assumptions into both implementation and expected bytes.
fixtures = [
  {"small_integer_42", "42", 42},
  {"integer_negative_1", "-1", -1},
  {"atom_hello", ":hello", :hello},
  {"tuple_ok_42", "{:ok, 42}", {:ok, 42}},
  {"binary_0001ff", "<<0, 1, 255>>", <<0, 1, 255>>},
  {"empty_list", "[]", []},
  {"list_1_2", "[1, 2]", [1, 2]}
]

otp = :erlang.system_info(:otp_release) |> List.to_string()
header = "# generator_otp=#{otp}\n# name\texpression\thex\n"
# Hex is reviewable and source-control friendly; every two hex characters
# represent one 8-bit wire octet.
rows =
  Enum.map_join(fixtures, "", fn {name, expression, term} ->
    hex = term |> :erlang.term_to_binary() |> Base.encode16(case: :lower)
    "#{name}\t#{expression}\t#{hex}\n"
  end)

path = Path.expand("../../fixtures/etf/manifest.tsv", __DIR__)
File.mkdir_p!(Path.dirname(path))
File.write!(path, header <> rows)
IO.puts(path)
