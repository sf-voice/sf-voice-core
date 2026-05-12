defmodule EllieAiWeb.MediaStreamingController do
  @moduledoc """
  upgrades the http connection to a websocket and hands control to
  `EllieAi.Telnyx.MediaStreamingSocket` (a `WebSock` impl).

  the websocket runs unauthenticated by design: telnyx connects from its
  own infrastructure and there is no session cookie / bearer to check.
  the implicit auth is "telnyx already proved who it is by signing the
  webhook that asked us to start streaming" — anyone connecting with a
  random ccid will simply not have a CallServer registered and their
  audio will go nowhere.

  reading the path: telnyx pulls the path we sent it in `streaming_start`
  (`/telnyx/media-streaming`); they don't append params. we don't need
  any either.
  """

  use EllieAiWeb, :controller

  alias EllieAi.Telnyx.MediaStreamingSocket

  def upgrade(conn, _params) do
    conn
    |> WebSockAdapter.upgrade(MediaStreamingSocket, %{}, timeout: 60_000)
    |> halt()
  end
end
