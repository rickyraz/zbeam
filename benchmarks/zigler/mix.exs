defmodule ZbeamResearch.MixProject do
  use Mix.Project

  def project do
    [
      app: :zbeam_research,
      version: "0.1.0",
      elixir: ">= 1.18.0",
      deps: [
        {:zigler,
         git: "https://github.com/E-xyza/zigler.git",
         ref: "feb80162d597ede227e9d4d5c9798a42beee9695",
         runtime: false}
      ]
    ]
  end

  def application, do: [extra_applications: [:logger, :crypto]]
end
