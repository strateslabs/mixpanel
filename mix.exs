defmodule Mixpanel.MixProject do
  use Mix.Project

  def project do
    [
      app: :mixpanel,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/project.plt"},
        plt_core_path: "priv/plts/core.plt",
        plt_add_apps: [:ex_unit]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Mixpanel.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:credo, "~> 1.7.0", only: [:dev, :test]},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:jason, "~> 1.4"},
      {:req, "~> 0.5.0"},
      {:mox, "~> 1.2.0", only: :test},
      {:styler, "~> 1.1", only: [:dev, :test]}
    ]
  end

  defp aliases do
    [
      check: [
        "format --check-formatted",
        "credo --all",
        "compile --warnings-as-errors",
        "dialyzer --format short"
      ]
    ]
  end
end
