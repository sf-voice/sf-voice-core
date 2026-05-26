[
  # paths excluded from workspace discovery + the dependency graph.
  # everything under deps/ and _build/ is build output; everything under
  # priv/data/ is the on-disk sqlite databases (one per app).
  ignore_paths: ~w[deps _build apps/*/deps apps/*/_build apps/*/priv/data elixir core],

  # cross-app linting checks. start empty; add as conventions emerge.
  # examples: enforce that every app declares a moduledoc, has a test/ dir,
  # uses the same elixir version, etc.
  checks: [],

  # `mix workspace.test.coverage` aggregates per-app coverage. tighten the
  # threshold once the suites grow.
  test_coverage: [
    allow_failure: [],
    threshold: 60,
    warning_threshold: 70,
    exporters: []
  ]
]
