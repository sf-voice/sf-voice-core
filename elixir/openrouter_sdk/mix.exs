defmodule OpenrouterSdk.MixProject do
  @moduledoc """
  scaffold. real code will be migrated out of apps/ellie_ai/lib/ellie_ai/providers/
  in a follow-up. not yet a member of the elixir workspace.
  """

  use Mix.Project

  def project do
    [
      app: :openrouter_sdk,
      version: "0.0.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "openrouter (and openai-compatible) chat + realtime client for elixir",
      package: package()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    []
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{}
    ]
  end
end
