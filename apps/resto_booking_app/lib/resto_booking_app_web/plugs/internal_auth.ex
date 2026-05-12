defmodule RestoBookingAppWeb.Plugs.InternalAuth do
  @moduledoc """
  bearer-token gate for the `/api/...` surface. ellie_ai is the only legitimate
  caller in v1, but this plug doesn't care who you are — only that you hold
  the shared `INTERNAL_API_TOKEN` env value.

  the secret is read once at app boot (`config/runtime.exs`) and stashed in
  application env, so we don't pay an env-read on every request and we get a
  single, loud failure at boot if it's missing in prod.

  401 (not 403) on a missing or wrong token because v1 has no notion of "you
  authenticated but lack permission" — there's just one role.
  """

  import Plug.Conn

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    expected = Application.get_env(:resto_booking_app, :internal_api_token)

    case fetch_bearer(conn) do
      {:ok, presented} ->
        if is_binary(expected) and expected != "" and
             Plug.Crypto.secure_compare(presented, expected) do
          conn
        else
          unauthorized(conn)
        end

      :error ->
        unauthorized(conn)
    end
  end

  defp fetch_bearer(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when token != "" -> {:ok, token}
      ["bearer " <> token] when token != "" -> {:ok, token}
      _ -> :error
    end
  end

  defp unauthorized(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, ~s({"errors":{"detail":"Unauthorized"}}))
    |> halt()
  end
end
