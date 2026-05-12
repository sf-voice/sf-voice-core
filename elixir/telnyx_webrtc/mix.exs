defmodule TelnyxWebrtc.MixProject do
  @moduledoc """
  scaffold. real code will be migrated out of apps/ellie_ai/lib/ellie_ai/telnyx/
  in a follow-up. not yet a member of the elixir workspace — adding it to
  mix.exs / workspace.lock is deferred until extraction.
  """

  use Mix.Project

  def project do
    [
      app: :telnyx_webrtc,
      version: "0.0.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "telnyx webrtc / media-streaming bindings for elixir",
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
