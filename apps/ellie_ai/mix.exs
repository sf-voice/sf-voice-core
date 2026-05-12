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

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.8.5"},
      {:phoenix_ecto, "~> 4.5"},
      # liveview for the staff ui. assets are bundled by esbuild + tailwind
      # v4 (see config/config.exs). vendor dir is for things we don't pull
      # from hex — currently just heroicons + topbar.
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_html, "~> 4.1"},
      # asset pipeline — runtime: :dev means the binaries only install in
      # the dev image; assets.deploy bakes the static output for prod.
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      # heroicons via @plugin so we can use `hero-x-mark` etc in heex.
      # `app: false, compile: false` — we only want the svg sources, not
      # the elixir app it ships with.
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      # shadcn-style component kit. `mix salad.setup` runs igniter to wire
      # tailwind, hooks, and tw_merge in one shot; `mix salad.add <name>`
      # copies individual components into lib/ellie_ai_web/components/ui/.
      # pinned to beta because the install story is meaningfully cleaner
      # than 0.14's manual setup.
      {:salad_ui, "~> 1.0.0-beta.3"},
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
      # s3 client for call audio archival. ExAws because it has the
      # multipart upload story baked in; switching the http adapter to
      # `hackney` because Req hasn't been blessed as an ExAws backend.
      {:ex_aws, "~> 2.5"},
      {:ex_aws_s3, "~> 2.5"},
      {:hackney, "~> 1.20"},
      {:sweet_xml, "~> 0.7"},
      # liveview test helpers parse rendered html — required dep for
      # `Phoenix.LiveViewTest.live/2`.
      {:lazy_html, ">= 0.1.0", only: :test}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind ellie_ai", "esbuild ellie_ai"],
      "assets.deploy": [
        "tailwind ellie_ai --minify",
        "esbuild ellie_ai --minify",
        "phx.digest"
      ],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
