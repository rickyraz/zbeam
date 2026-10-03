[label, job, size, count] = System.argv()

result =
  ZbeamResearch.Comparison.run(label, job, String.to_integer(size), String.to_integer(count))

IO.puts("RESULT " <> JSON.encode!(result))
