defmodule SfVoice.MixWorkspace do
  @moduledoc """
  workspace root for sf-voice's elixir monorepo.

  this project is a workspace, not a runnable application — it has no source
  code under `lib/` and starts no OTP application. its job is to declare the
  workspace and its tooling deps. real code lives in `apps/<name>/`, each a
  fully self-contained Mix project with its own `deps/`, `_build/`, and
  `mix.lock`.

  add a new app:
      mix new apps/<name>           # plain library
      mix phx.new apps/<name> ...   # phoenix backend

  list / run across apps:
      mix workspace.list
      mix workspace.run -t test
      mix workspace.run -t format
  """

  use Mix.Project

  def project do
    [
      app: :sf_voice,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: [],
      deps: deps(),
      workspace: [
        type: :workspace
      ],
      lockfile: "workspace.lock"
    ]
  end

  def application do
    [extra_applications: []]
  end

  defp deps do
    [
      {:workspace, "~> 0.2.0"}
    ]
  end
end
