defmodule EllieAi.Tools.UpsertCustomer do
  @moduledoc "write caller details into ellie's local customer_summary row. never posts to resto."

  @behaviour EllieAi.Tools.Tool

  alias EllieAi.{Customers, Orgs}
  alias EllieAi.Customers.CustomerSummary

  @impl true
  def name, do: "upsert_customer"

  @impl true
  def description do
    """
    Save what we've learned about the caller into ellie's local record.
    Call this once you have the caller's name (and optionally email or
    a note). The phone is required — use the caller's number from the
    customer_intro line of your prompt. Only include the fields you
    actually have; partial updates are fine. Safe to call multiple
    times during a call as more info comes in. This does NOT create a
    reservation — that happens later via create_reservation.
    """
  end

  @impl true
  def parameters_schema do
    %{
      type: "object",
      properties: %{
        phone: %{
          type: "string",
          description:
            "Caller's phone number in any reasonable format — ellie normalizes to E.164."
        },
        first_name: %{type: "string", description: "Caller's first name."},
        last_name: %{type: "string", description: "Caller's last name. Optional."},
        salutation: %{type: "string", description: "Mr, Ms, Dr, etc. Optional."},
        email: %{type: "string", description: "Caller's email if they volunteer it. Optional."},
        notes: %{
          type: "string",
          description:
            "A short freeform note about the caller (allergies, preferences, " <>
              "VIP, etc). Overwrites any existing notes — pass the merged value."
        }
      },
      required: ["phone"],
      additionalProperties: false
    }
  end

  @impl true
  def execute(%{"phone" => phone} = args, %{org: %Orgs.Org{} = org}) when is_binary(phone) do
    attrs = stringy_to_atoms(args)

    case Customers.set_name(org, phone, attrs) do
      {:ok, %CustomerSummary{} = summary} ->
        {:ok, %{customer: format(summary)}}

      {:error, {:permanent, _} = err} ->
        {:error, err}

      {:error, reason} ->
        {:error, {:permanent, "could not save customer: #{inspect(reason)}"}}
    end
  end

  def execute(_, %{org: %Orgs.Org{}}),
    do: {:error, {:permanent, "missing required arg: phone"}}

  def execute(_, _),
    do: {:error, {:permanent, "missing :org in execution context"}}

  defp stringy_to_atoms(args) do
    args
    |> Map.drop(["phone"])
    |> Enum.reduce(%{}, fn
      {_, v}, acc when v in [nil, ""] -> acc
      {k, v}, acc -> Map.put(acc, String.to_atom(k), v)
    end)
  end

  defp format(%CustomerSummary{} = c) do
    %{
      id: c.id,
      display_name: CustomerSummary.display_name(c),
      first_name: c.first_name,
      last_name: c.last_name,
      salutation: c.salutation,
      phone: c.phone_e164,
      email: c.email,
      notes: c.notes
    }
  end
end
