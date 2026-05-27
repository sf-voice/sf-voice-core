defmodule EllieAi.Calls.AudioBridgeStub do
  @moduledoc """
  test bridge that registers like AudioBridge without opening a websocket.
  """

  use GenServer

  alias EllieAi.Calls.CallRegistry

  def child_spec(%{ccid: ccid} = args) when is_binary(ccid) do
    %{
      id: {__MODULE__, ccid},
      start: {__MODULE__, :start_link, [args]},
      type: :worker,
      restart: :transient,
      shutdown: 5_000
    }
  end

  def start_link(%{ccid: ccid} = state) when is_binary(ccid) do
    GenServer.start_link(__MODULE__, state, name: CallRegistry.via_audio_bridge(ccid))
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_info(_message, state), do: {:noreply, state}
end
