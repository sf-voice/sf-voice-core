defmodule EllieAiWeb.HealthController do
  @moduledoc """
  health endpoints for the blue-green deploy script. `/health` is a
  liveness check; `/health/active_calls` returns the running call count
  + drain flag so the script can wait for in-flight calls before stopping
  the blue container.
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
