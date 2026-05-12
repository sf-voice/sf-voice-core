defmodule EllieAiWeb.HealthController do
  @moduledoc """
  health endpoints for the blue-green deploy script.

    * GET /health        — 200 if the app is up. no auth.
    * GET /health/active_calls — number of running call trees, plus the
                                 drain flag. used by the deploy script to
                                 wait for in-flight calls to finish before
                                 stopping the blue container.
  """

  use EllieAiWeb, :controller

  def show(conn, _params), do: json(conn, %{ok: true})

  def active_calls(conn, _params) do
    count =
      DynamicSupervisor.count_children(EllieAi.Calls.CallSupervisor)
      |> Map.get(:active, 0)

    json(conn, %{active_calls: count, draining: EllieAi.Drain.draining?()})
  end
end
