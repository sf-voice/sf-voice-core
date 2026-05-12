defmodule EllieAi.Telnyx.CacheBodyReader do
  @moduledoc """
  stashes the raw http body in `conn.assigns.raw_body` before plug.parsers
  consumes it — telnyx signature verification needs the exact bytes telnyx
  sent, and json decoding loses key ordering / whitespace / number formatting.
  """

  # plug may call this multiple times if the body is chunked, so we accumulate.
  # `:more` means there's still body left to read — plug.parsers will call us
  # again. we still stash the chunk so the final assembled raw_body matches
  # what telnyx signed.
  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        conn = Plug.Conn.assign(conn, :raw_body, [body | conn.assigns[:raw_body] || []])
        {:ok, body, conn}

      {:more, body, conn} ->
        conn = Plug.Conn.assign(conn, :raw_body, [body | conn.assigns[:raw_body] || []])
        {:more, body, conn}

      {:error, _} = err ->
        err
    end
  end
end
