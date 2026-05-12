defmodule EllieAi.Calls.CallTree do
  @moduledoc """
  per-call supervision tree. `:rest_for_one` — CallServer crash restarts
  everything; later siblings restart with their predecessors. CallServer
  is first because it owns durable state + registry registration.
  one tree per active call under CallSupervisor (DynamicSupervisor).
  """

  use Supervisor

  alias EllieAi.Calls.{Archivist, CallServer, AudioBridge, VadGate}

  @doc "`:temporary` — if the tree dies, the call is gone. caller redials; no reincarnation."
  def child_spec(args) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [args]},
      type: :supervisor,
      restart: :temporary,
      shutdown: :infinity
    }
  end

  def start_link(%{ccid: ccid} = args) when is_binary(ccid) do
    Supervisor.start_link(__MODULE__, args, name: name_for(ccid))
  end

  defp name_for(ccid), do: {:global, {__MODULE__, ccid}}

  @impl true
  def init(%{org: org, ccid: ccid, payload: payload}) do
    # publish once; children pick it up via Memory.bootstrap_from(ccid).
    EllieAi.Calls.Memory.publish_context(org, ccid)

    children = [
      {CallServer, %{ccid: ccid, payload: payload}},
      {AudioBridge, %{ccid: ccid}},
      {VadGate, %{ccid: ccid}},
      {Archivist, %{ccid: ccid}}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
