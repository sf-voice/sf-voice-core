defmodule EllieAi.Tools.ModifyReservation do
  @moduledoc "change the time of one of the caller's reservations."

  @behaviour EllieAi.Tools.Tool

  alias EllieAi.{Orgs, Prompts, Resto}
  alias EllieAi.Calls.Memory
  alias EllieAi.Tools.CustomerPreconditions

  @impl true
  def name, do: "modify_reservation"

  @impl true
  def description do
    """
    Change the time of an existing reservation belonging to the current
    caller. Confirm party_size and starts_at against what the caller
    says before calling — the tool refuses if they don't match a
    reservation on file.
    """
  end

  @impl true
  def parameters_schema do
    %{
      type: "object",
      properties: %{
        party_size: %{type: "integer", minimum: 1,
          description: "Party size on the existing reservation. Used to match."},
        starts_at: %{type: "string",
          description: "Existing reservation's start time, ISO 8601. Used to match."},
        new_starts_at: %{type: "string",
          description: "Requested new start time, ISO 8601."}
      },
      required: ["party_size", "starts_at", "new_starts_at"],
      additionalProperties: false
    }
  end

  @impl true
  def execute(
        %{"party_size" => size, "starts_at" => starts_at, "new_starts_at" => new_starts_at},
        %{org: %Orgs.Org{} = org, ccid: ccid}
      )
      when is_integer(size) and is_binary(starts_at) and is_binary(new_starts_at) and
             is_binary(ccid) do
    with :ok <- CustomerPreconditions.check(ccid),
         {:ok, reservation} <- find_one(ccid, size, starts_at),
         {:ok, updated} <- Resto.update_reservation(org, reservation.id, %{starts_at: new_starts_at}) do
      Memory.update_reservation(ccid, reservation.id, %{starts_at: new_starts_at})
      Prompts.re_render!(ccid)
      {:ok, %{reservation: updated}}
    else
      {:error, :not_found} -> {:error, {:permanent, "no reservation matches that party size and time"}}
      {:error, :ambiguous} -> {:error, {:permanent, "more than one reservation matches — ask the caller to be more specific"}}
      {:error, {:transient, _}} = err -> err
      {:error, {:permanent, _}} = err -> err
      {:error, other} -> {:error, {:permanent, inspect(other)}}
    end
  end

  def execute(_, _),
    do: {:error, {:permanent, "missing required args: party_size + starts_at + new_starts_at"}}

  defp find_one(ccid, size, starts_at) do
    matches =
      ccid
      |> Memory.reservations()
      |> Enum.filter(fn r -> r.party_size == size and r.starts_at == starts_at end)

    case matches do
      [one] -> {:ok, one}
      [] -> {:error, :not_found}
      [_ | _] -> {:error, :ambiguous}
    end
  end
end
