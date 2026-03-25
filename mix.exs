defmodule Relayixir.MixProject do
  use Mix.Project

  def project do
    [
      app: :relayixir,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Relayixir.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:bandit, "~> 1.0"},
      {:plug, "~> 1.15"},
      {:mint, "~> 1.6"},
      {:mint_web_socket, "~> 1.0"},
      {:telemetry, "~> 1.2"},
      {:plug_cowboy, "~> 2.7", only: :test},
      {:websock_adapter, "~> 0.5"}
    ]
  end
end
