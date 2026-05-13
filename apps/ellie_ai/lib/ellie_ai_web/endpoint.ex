defmodule EllieAiWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :ellie_ai


  plug Plug.Logger, log: :debug

  @session_options [
    store: :cookie,
    key: "_ellie_ai_key",
    signing_salt: "MZaKPD43",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]

  # internal VAD service — consumed by the rust api (and future consumers)
  # over proxy_net at ws://ellie-ai:4001/socket/vad/websocket. auth is
  # the shared INTERNAL_API_TOKEN bearer, checked in VadSocket.connect/3.
  socket "/socket/vad", EllieAiWeb.VadSocket,
    websocket: true,
    longpoll: false

  plug Plug.Static,
    at: "/",
    from: :ellie_ai,
    gzip: not code_reloading?,
    only: EllieAiWeb.static_paths(),
    raise_on_missing_only: code_reloading?

  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]


  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    body_reader: {EllieAi.Telnyx.CacheBodyReader, :read_body, []},
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug EllieAiWeb.Router
end
