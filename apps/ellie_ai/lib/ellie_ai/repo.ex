defmodule EllieAi.Repo do
  use Ecto.Repo,
    otp_app: :ellie_ai,
    adapter: Ecto.Adapters.SQLite3
end
