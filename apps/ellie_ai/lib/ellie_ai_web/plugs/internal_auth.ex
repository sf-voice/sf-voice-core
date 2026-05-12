defmodule EllieAiWeb.Plugs.InternalAuth do
  @moduledoc """
  bearer auth for ellie's internal `/api/...` endpoints. compares the
  Authorization header against `:internal_api_token` from runtime
  config. used by the tool-replay endpoint and any future staff-only
  json apis.

  matches resto's `RestoBookingAppWeb.Plugs.InternalAuth` shape so the
  same env var works on both sides.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    expected = Application.get_env(:ellie_ai, :internal_api_token)

    case get_req_header(conn, "authorization") do
      ["Bearer " <> ^expected] when is_binary(expected) and expected != "" ->
        conn

      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(:unauthorized, ~s({"error":"unauthorized"}))
        |> halt()
    end
  end
end
