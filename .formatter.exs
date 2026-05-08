# root formatter — only formats workspace-level files. each app under apps/
# carries its own .formatter.exs with phoenix/ecto plugins and import_deps.
[
  inputs: ["{mix,.formatter,.workspace}.exs"],
  subdirectories: ["apps/*"]
]
