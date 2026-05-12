defmodule EllieAi.Tools.RequestHumanHandoff do
  @moduledoc "transfer the caller to a human staff member via Escalator."

  @behaviour EllieAi.Tools.Tool

  alias EllieAi.Calls.Escalator
  alias EllieAi.Orgs

  @impl true
  def name, do: "request_human_handoff"

  @impl true
  def description do
    """
    Transfer the caller to a human staff member. Use this when the
    caller asks for a person, sounds frustrated, raises an allergy
    issue, or asks something you cannot resolve (refunds, special
    accommodations, complaints). The system will dial the restaurant's
    staff line and bridge them in. Once you've called this tool,
    politely tell the caller you're putting them through and stop
    talking.
    """
  end

  @impl true
  def parameters_schema do
    %{
      type: "object",
      properties: %{
        reason: %{
          type: "string",
          description: "Short summary of why escalation is needed."
        }
      },
      required: [],
      additionalProperties: false
    }
  end

  @impl true
  def execute(args, %{org: %Orgs.Org{} = org, ccid: ccid}) when is_binary(ccid) do
    reason = Map.get(args, "reason", "model-initiated handoff")

    case Escalator.escalate(org, ccid) do
      :ok -> {:ok, %{escalating: true, reason: reason}}
      {:error, {:permanent, msg}} -> {:error, {:permanent, msg}}
      {:error, reason} -> {:error, {:transient, inspect(reason)}}
    end
  end

  def execute(_, _), do: {:error, {:permanent, "missing :org / :ccid in context"}}
end
