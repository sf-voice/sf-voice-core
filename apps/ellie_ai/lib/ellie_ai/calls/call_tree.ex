defmodule EllieAi.Calls.CallTree do
  @moduledoc """
  per-call supervision tree. `:rest_for_one` so:

    * if `CallServer` (the orchestrator) crashes → restart everything
    * if `AudioBridge` (openai realtime ws) crashes → restart it (and any
      siblings started after it)
    * if `VadGate` crashes → restart only it

  ordering is intentional. CallServer is started first because it owns
  the durable state and registry registration; the audio workers attach
  to it.

  the tree itself is started under the top-level CallSupervisor
  (DynamicSupervisor). one tree per active call, identified by ccid.
  """

  use Supervisor

  alias EllieAi.Calls.{Archivist, CallServer, AudioBridge, VadGate}

  @doc """
  child spec for the DynamicSupervisor parent. `:temporary` — if the
  per-call tree dies for any reason, the call is gone. the caller dials
  again; we don't try to reincarnate state mid-call.
  """
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
    # publish org once into the shared per-call context. children read
    # it back via `Flag.bootstrap_from(ccid)` in their own init — no
    # need to thread `org` through every worker's start args.
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
