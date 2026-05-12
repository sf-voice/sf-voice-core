defmodule EllieAiWeb.AdminDrainController do
  @moduledoc """
  POST /admin/drain — set the global drain flag. internal-api auth (the
  deploy script holds the bearer). idempotent.
  """

  use EllieAiWeb, :controller

  def drain(conn, _params) do
    :ok = EllieAi.Drain.drain!()
    json(conn, %{draining: true})
  end
end
