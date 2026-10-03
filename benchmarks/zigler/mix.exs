defmodule ZbeamResearch.MixProject do
  use Mix.Project

  def project do
    [
      app: :zbeam_research,
      version: "0.1.0",
      elixir: ">= 1.16.0",
      deps: [{:zigler, "== 0.16.0", runtime: false}]
    ]
  end

  def application, do: [extra_applications: [:logger, :crypto]]
end
