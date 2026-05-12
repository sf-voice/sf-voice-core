defmodule EllieAiWeb.OrgSwitchController do
  @moduledoc """
  switches the active org for the current session and redirects back to
  the referring page. uses a plain POST + form so it works without js;
  LiveView re-mounts pick up the new org from session on full reload.
  """

  use EllieAiWeb, :controller

  alias EllieAi.Orgs

  def switch(conn, %{"org_id" => org_id}) do
    case Orgs.get(org_id) do
      nil ->
        conn
        |> put_flash(:error, "That org doesn't exist anymore.")
        |> redirect_back()

      org ->
        conn
        |> put_session(:current_org_id, org.id)
        |> put_flash(:info, "Switched to #{org.name}")
        |> redirect_back()
    end
  end

  defp redirect_back(conn) do
    case get_req_header(conn, "referer") do
      [referer | _] -> redirect(conn, external: referer)
      _ -> redirect(conn, to: "/")
    end
  end
end
