defmodule EllieAiWeb.VadSocket do
  @moduledoc """
  websocket transport for the internal VAD service. mounted at
  `/socket/vad` (see `EllieAiWeb.Endpoint`).

  caddy doesn't route any public hostname to this path — the socket is
  only reachable from inside `proxy_net` (rust api today, future
  consumers later). auth is the shared `INTERNAL_API_TOKEN` bearer,
  same secret the rust api will send on every request.
  """

  use Phoenix.Socket

  channel "vad:*", EllieAiWeb.VadChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    expected = Application.get_env(:ellie_ai, :internal_api_token)

    cond do
      not is_binary(expected) or expected == "" -> :error
      Plug.Crypto.secure_compare(token, expected) -> {:ok, socket}
      true -> :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  # no per-user identity — every connection is "the trusted internal
  # caller." returning nil disables presence/broadcast routing by id.
  @impl true
  def id(_socket), do: nil
end
