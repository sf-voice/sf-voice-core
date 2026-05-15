defmodule EllieAi.Tools.LookupAvailability do
  @moduledoc "ask resto which tables have which intervals booked on a date."

  @behaviour EllieAi.Tools.Tool

  alias EllieAi.{Orgs, RestoClient}
  alias EllieAi.Tools.Tool

  @impl true
  def name, do: "lookup_availability"

  @impl true
  def description do
    """
    Look up which tables are taken on a given date. Returns each table
    with the list of existing reservations (start, end, party size).
    Use this before suggesting a time to the caller. Date must be in
    YYYY-MM-DD format — resolve relative dates ("tomorrow", "next
    friday") before calling.
    """
  end

  @impl true
  def parameters_schema do
    %{
      type: "object",
      properties: %{
        date: %{
          type: "string",
          description: "Reservation date in YYYY-MM-DD format."
        }
      },
      required: ["date"],
      additionalProperties: false
    }
  end

  @impl true
  def execute(%{"date" => date}, %{org: %Orgs.Org{} = org}) when is_binary(date) do
    case RestoClient.get_availability(org, date) do
      {:ok, body} -> {:ok, body}
      {:error, :not_found} -> {:ok, %{date: date, tables: []}}
      {:error, {:transient, _}} = err -> err
      {:error, {:permanent, reason}} -> {:error, {:permanent, Tool.format_reason(reason)}}
    end
  end

  def execute(%{"date" => _}, _), do: {:error, {:permanent, "missing :org in execution context"}}
  def execute(_, _), do: {:error, {:permanent, "missing required arg: date"}}
end
