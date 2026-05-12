defmodule EllieAiWeb.Plugs.OrgSession do
  @moduledoc """
  resolves the current org for the staff console and stores it in the
  session as `:current_org_id`.

  v0 has no auth — anyone hitting the URL switches their own session.
  fine for staff console on a local network; flag if we ever go public.

  resolution order:
    1. session's `:current_org_id`, if it still points at a real org
    2. first org by name (alphabetical via `Orgs.list/0`) as a default
    3. nil if nothing is seeded

  sets the value back into the session so subsequent requests are stable
  and so LiveView's `on_mount` can read it via the session map.
  """

  import Plug.Conn

  alias EllieAi.Orgs

  @session_key :current_org_id

  def init(opts), do: opts

  def call(conn, _opts) do
    stored = get_session(conn, @session_key)
    org = resolve(stored)

    case org do
      nil ->
        conn

      %Orgs.Org{id: id} when id != stored ->
        put_session(conn, @session_key, id)

      _ ->
        conn
    end
  end

  defp resolve(nil), do: default()

  defp resolve(id) when is_binary(id) do
    case Orgs.get(id) do
      nil -> default()
      org -> org
    end
  end

  defp default do
    case Orgs.list() do
      [%Orgs.Org{} = org | _] -> org
      _ -> nil
    end
  end
end
