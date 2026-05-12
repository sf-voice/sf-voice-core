defmodule EllieAiWeb.MediaStreamingController do
  @moduledoc """
  upgrades to a websocket and hands control to `MediaStreamingSocket`.
  unauthenticated by design: telnyx connects from its own infra, and
  implicit auth is the signed webhook that asked us to start streaming.
  random ccids land nowhere because no CallServer is registered for them.
  """

  use EllieAiWeb, :controller

  alias EllieAi.Telnyx.MediaStreamingSocket

  def upgrade(conn, _params) do
    conn
    |> WebSockAdapter.upgrade(MediaStreamingSocket, %{}, timeout: 60_000)
    |> halt()
  end
end
