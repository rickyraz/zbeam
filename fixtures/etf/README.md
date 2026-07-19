# ETF Golden Vectors

`manifest.tsv` contains deterministic terms encoded by the recorded OTP generator. Regenerate with:

```sh
elixir scripts/interop/generate_etf_fixtures.exs
```

Columns are fixture name, Erlang/Elixir source expression, and lowercase hexadecimal ETF bytes. Generated vectors cover stable term tags only; they do not replace the OTP 25–27 interoperability matrix.
