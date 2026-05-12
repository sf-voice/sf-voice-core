# root formatter — only formats workspace-level files. each app under apps/
# carries its own .formatter.exs with phoenix/ecto plugins and import_deps.
#
# we deliberately do NOT traverse into apps/* via `subdirectories` here.
# that's the standard Mix umbrella pattern, but this project is a
# `:workspace` (each app is a separate Mix project with its own deps/).
# Zed/ElixirLS evaluates `subdirectories` against the workspace root's
# mix.exs (which has no :phoenix), so `import_deps: [:phoenix]` inside
# each app's .formatter.exs explodes with "Unknown dependency :phoenix".
#
# format apps from inside their own dir (`cd apps/<name> && mix format`)
# or across the workspace via `mix workspace.run -t format`. Zed still
# finds the per-app formatter via nearest-file lookup when formatting on
# save.
[
  inputs: ["{mix,.formatter,.workspace}.exs", "*/{mix,.formatter,.workspace}.exs"]
]
