defmodule EllieAi.MixProject do
  use Mix.Project

  def project do
    [
      app: :ellie_ai,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {EllieAi.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.5"},
      {:phoenix_ecto, "~> 4.5"},
      # liveview for the staff ui (homepage + call detail). vendored js
      # served from priv/static/assets; tailwind comes from cdn — no
      # esbuild/tailwind dep dance for v0.
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_html, "~> 4.1"},
      {:ecto_sql, "~> 3.13"},
      {:ecto_sqlite3, ">= 0.0.0"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      # http client for the read-only resto integration. retry: :transient
      # handles network noise without us hand-rolling backoff.
      {:req, "~> 0.5"},
      # E.164 normalization on the boundary — resto trusts whatever ellie
      # sends, so ellie does the work.
      {:ex_phone_number, "~> 0.4"},
      # outbound websocket client — used to bridge to OpenAI Realtime.
      # GenServer-shaped so it slots into a per-call supervision tree.
      {:websockex, "~> 0.4.3"},
      # ONNX runtime via rust NIF. used to run silero-vad locally on
      # μ-law-decoded 8kHz pcm. compiles a rust extension on first install
      # (~2-5 min on m-series) and downloads onnxruntime binaries.
      {:ortex, "~> 0.1.10"},
      # tiny http server for testing the resto client without a real network.
      {:bypass, "~> 2.1", only: :test},
      # liveview test helpers parse rendered html — required dep for
      # `Phoenix.LiveViewTest.live/2`.
      {:lazy_html, ">= 0.1.0", only: :test}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
