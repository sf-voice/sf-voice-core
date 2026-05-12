defmodule RestoBookingAppWeb.Plugs.OrgScope do
  @moduledoc """
  resolves the `:org_slug` path param into an org and assigns it to
  the conn so every controller below can read it without re-querying.

  on miss returns 404 with a json body — multi-tenant security boundary,
  not a routing concern. mounted under the `/api/orgs/:org_slug` scope
  in the router.
  """

  import Plug.Conn

  alias RestoBookingApp.Orgs

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case conn.path_params do
      %{"org_slug" => slug} when is_binary(slug) and slug != "" ->
        case Orgs.get_by_slug(slug) do
          nil ->
            not_found(conn)

          org ->
            conn
            |> assign(:org, org)
            |> assign(:org_id, org.id)
        end

      _ ->
        not_found(conn)
    end
  end

  defp not_found(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(404, ~s({"errors":{"detail":"Unknown org"}}))
    |> halt()
  end
end
