defmodule EllieAi.Tools.CreateReservation do
  @moduledoc "book a reservation for the current caller."

  @behaviour EllieAi.Tools.Tool

  alias EllieAi.{Customers, Orgs, Resto}
  alias EllieAi.Customers.CustomerSummary
  alias EllieAi.Tools.CustomerPreconditions

  require Logger

  @impl true
  def name, do: "create_reservation"

  @impl true
  def description do
    """
    Book a reservation. The caller must already have a name on file —
    for first-time callers, call upsert_customer with their name first.
    starts_at must be ISO 8601 with timezone (e.g.
    2026-05-20T19:30:00-07:00). Returns the reservation and a
    management token; remember the token in case the caller wants to
    modify or cancel later.
    """
  end

  @impl true
  def parameters_schema do
    %{
      type: "object",
      properties: %{
        starts_at: %{type: "string", description: "ISO 8601 datetime with timezone."},
        party_size: %{type: "integer", minimum: 1},
        table_id: %{type: "string", description: "Optional — resto picks one if omitted."},
        notes: %{type: "string"}
      },
      required: ["starts_at", "party_size"],
      additionalProperties: false
    }
  end

  @impl true
  def execute(args, %{org: %Orgs.Org{} = org, ccid: ccid}) when is_binary(ccid) do
    with :ok <- CustomerPreconditions.check(ccid),
         {:ok, summary} <- resolve_summary(org, ccid),
         {:ok, payload} <- build_payload(summary, args),
         {:ok, reservation} <- Resto.create_reservation(org, payload) do
      maybe_reconcile(org, summary, reservation)
      {:ok, %{reservation: reservation}}
    else
      {:error, {:transient, _}} = err -> err
      {:error, {:permanent, _}} = err -> err
      {:error, :not_found} -> {:error, {:permanent, "resto rejected the booking"}}
      {:error, :customer_not_found} -> {:error, {:permanent, "no customer on file for this call"}}
      {:error, other} -> {:error, {:permanent, inspect(other)}}
    end
  end

  def execute(_, _), do: {:error, {:permanent, "missing :org / :ccid in context"}}

  defp resolve_summary(%Orgs.Org{} = org, ccid) do
    with %{from_phone: from} when is_binary(from) <- EllieAi.Calls.get_by_ccid(ccid),
         {:ok, %CustomerSummary{} = summary} <- Customers.lookup_by_phone(org, from) do
      {:ok, summary}
    else
      _ -> {:error, :customer_not_found}
    end
  end

  defp build_payload(%CustomerSummary{} = summary, %{"starts_at" => start, "party_size" => size} = args)
       when is_binary(start) and is_integer(size) and size > 0 do
    customer =
      %{
        id: summary.id,
        phone: summary.phone_e164,
        first_name: summary.first_name,
        last_name: summary.last_name,
        salutation: summary.salutation,
        email: summary.email
      }
      |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)
      |> Map.new()

    payload =
      %{
        customer: customer,
        starts_at: start,
        party_size: size,
        table_id: Map.get(args, "table_id"),
        notes: Map.get(args, "notes")
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    {:ok, payload}
  end

  defp build_payload(_, _),
    do: {:error, {:permanent, "missing required args: starts_at + party_size"}}

  defp maybe_reconcile(%Orgs.Org{} = org, %CustomerSummary{id: local_id, phone_e164: phone}, %{
         "customer" => %{"id" => resto_id} = customer_payload
       })
       when is_binary(resto_id) and resto_id != local_id do
    case Customers.reconcile_id(org, phone, customer_payload) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "create_reservation: reconcile_id failed after booking — " <>
            "local=#{local_id} resto=#{resto_id} reason=#{inspect(reason)}"
        )
    end
  end

  defp maybe_reconcile(_, _, _), do: :ok
end
