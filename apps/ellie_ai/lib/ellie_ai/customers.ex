defmodule EllieAi.Customers do
  @moduledoc """
  ellie's customer read-model context. multi-tenant: every public
  function takes an `%EllieAi.Orgs.Org{}` (or `org_id`) so cache reads
  and resto fallbacks both resolve to the right org.

  the keystone read for the call loop is `lookup_by_phone/2`. waterfall:
    1. local read on `(org_id, phone_e164)` — fast, no network.
    2. miss → `EllieAi.RestoClient.get_customer_by_phone/2`. on hit, upsert
       the summary so the next call is fast.
    3. miss everywhere → `:not_found`. step 3's "ask the caller" lives
       at the realtime tool layer.

  `customer_summary.id` is the SAME uuid resto stores in `customers.id`.
  when the async reconcile or a booking response surfaces an id mismatch,
  `reconcile_id/3` deletes the local stub and reinserts under resto's id.
  """

  import Ecto.Query, except: [update: 2, update: 3]

  alias EllieAi.Customers.CustomerSummary
  alias EllieAi.Orgs.Org
  alias EllieAi.{Repo, RestoClient}

  require Logger

  @doc """
  returns:

    * `{:ok, %CustomerSummary{}}` — local hit, or resto hit on fallback
    * `:not_found` — neither cache nor resto knows this phone
    * `{:error, reason}` — resto reachable but errored
  """
  def lookup_by_phone(%Org{} = org, phone) when is_binary(phone) do
    case normalize_or_error(phone) do
      {:ok, e164} ->
        case Repo.get_by(CustomerSummary, org_id: org.id, phone_e164: e164) do
          %CustomerSummary{} = hit -> {:ok, hit}
          nil -> fallback_to_resto(org, e164)
        end

      {:error, _} = err ->
        err
    end
  end

  @doc "newest activity first."
  def list(org_id, opts \\ []) when is_binary(org_id) do
    limit = Keyword.get(opts, :limit, 500)

    from(c in CustomerSummary,
      where: c.org_id == ^org_id,
      order_by: [desc: c.last_seen_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  def get(org_id, id) when is_binary(org_id) and is_binary(id) do
    Repo.get_by(CustomerSummary, org_id: org_id, id: id)
  end

  @doc """
  invoked by `CallServer.init/1` the moment a call lands so every
  subsequent tool is working against a real row. the row is **local-only**
  — no resto POST until the caller actually books something. an async
  resto reconcile may later swap our local id for resto's via
  `reconcile_id/3`. idempotent under the unique index on
  `(org_id, phone_e164)`.
  """
  @spec ensure_local(Org.t(), String.t()) ::
          {:ok, CustomerSummary.t()} | {:error, term()}
  def ensure_local(%Org{} = org, phone) when is_binary(phone) do
    with {:ok, e164} <- normalize_or_error(phone) do
      result =
        case Repo.get_by(CustomerSummary, org_id: org.id, phone_e164: e164) do
          %CustomerSummary{} = existing ->
            touch_last_seen(existing)

          nil ->
            insert_stub(org.id, e164)
        end

      # back-stamp any calls that landed before this row existed so the
      # /customers/:id feed picks up the call records via the FK.
      case result do
        {:ok, %CustomerSummary{id: id}} -> EllieAi.Calls.stamp_customer_id(org.id, e164, id)
        _ -> :ok
      end

      result
    end
  end

  defp touch_last_seen(%CustomerSummary{} = row) do
    row
    |> CustomerSummary.changeset(%{last_seen_at: now()})
    |> Repo.update()
  end

  defp insert_stub(org_id, e164) do
    ts = now()

    %CustomerSummary{}
    |> CustomerSummary.changeset(%{
      org_id: org_id,
      phone_e164: e164,
      first_seen_at: ts,
      last_seen_at: ts,
      # sentinel: we haven't talked to resto about this row yet. the
      # async reconcile or a booking response overwrites this on first sync touch.
      last_synced_at: ts
    })
    |> Repo.insert()
    |> case do
      {:ok, row} = ok ->
        Logger.info("customers.ensure_local: stub inserted org_id=#{org_id} id=#{row.id}")
        ok

      {:error, %Ecto.Changeset{errors: errors}} = err ->
        # most likely a unique-constraint race with a parallel call;
        # the row exists, just re-fetch it.
        if Keyword.has_key?(errors, :phone_e164) do
          case Repo.get_by(CustomerSummary, org_id: org_id, phone_e164: e164) do
            %CustomerSummary{} = row -> {:ok, row}
            nil -> err
          end
        else
          err
        end
    end
  end

  @doc """
  invoked by both the `upsert_customer` tool (AI-driven) and the staff
  inline-edit UI. only the fields provided are written; nil/missing keys
  are ignored.
  """
  @spec set_name(Org.t(), String.t(), map()) ::
          {:ok, CustomerSummary.t()} | {:error, term()}
  def set_name(%Org{} = org, phone, attrs) when is_binary(phone) and is_map(attrs) do
    with {:ok, e164} <- normalize_or_error(phone),
         {:ok, row} <- ensure_local(org, e164) do
      row
      |> CustomerSummary.changeset(Map.put(attrs, :last_seen_at, now()))
      |> Repo.update()
    end
  end

  @doc """
  caller is trusted to scope to the right org (we still verify via the
  WHERE clause).
  """
  @spec update_by_id(String.t(), String.t(), map()) ::
          {:ok, CustomerSummary.t()} | {:error, term()}
  def update_by_id(org_id, id, attrs)
      when is_binary(org_id) and is_binary(id) and is_map(attrs) do
    case Repo.get_by(CustomerSummary, org_id: org_id, id: id) do
      nil ->
        {:error, :not_found}

      row ->
        row
        |> CustomerSummary.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  called by the async resto-lookup task on call landing, and by
  `CreateReservation` after a successful booking, whenever resto's
  customer id differs from the local row's. sqlite PKs are immutable so
  we delete + reinsert; back-stamps `calls.customer_id` so the call
  timeline still resolves. no FK from anywhere else points at
  customer_summary, so the delete is safe.
  """
  @spec reconcile_id(Org.t(), String.t(), map()) ::
          {:ok, CustomerSummary.t()} | {:error, term()}
  def reconcile_id(%Org{} = org, phone, %{"id" => resto_id} = payload)
      when is_binary(phone) and is_binary(resto_id) do
    with {:ok, e164} <- normalize_or_error(phone) do
      attrs = resto_payload_to_attrs(org.id, e164, payload)

      Repo.transaction(fn ->
        existing = Repo.get_by(CustomerSummary, org_id: org.id, phone_e164: e164)

        cond do
          is_nil(existing) ->
            insert_from_attrs(attrs)

          existing.id == resto_id ->
            # already aligned — just refresh name/notes/email from resto.
            existing
            |> CustomerSummary.changeset(attrs)
            |> Repo.update()
            |> unwrap_or_rollback()

          true ->
            Logger.info(
              "customers.reconcile_id: swapping local id #{existing.id} → resto id #{resto_id} " <>
                "(org=#{org.slug} phone=#{e164})"
            )

            Repo.delete!(existing)
            insert_from_attrs(attrs)
        end
      end)
      |> case do
        {:ok, row} ->
          EllieAi.Calls.stamp_customer_id(org.id, e164, row.id)
          {:ok, row}

        {:error, _} = err ->
          err
      end
    end
  end

  defp insert_from_attrs(attrs) do
    %CustomerSummary{}
    |> CustomerSummary.changeset(attrs)
    |> Repo.insert()
    |> unwrap_or_rollback()
  end

  defp unwrap_or_rollback({:ok, row}), do: row
  defp unwrap_or_rollback({:error, cs}), do: Repo.rollback(cs)

  defp resto_payload_to_attrs(org_id, e164, payload) do
    %{
      id: payload["id"],
      org_id: org_id,
      salutation: payload["salutation"],
      first_name: payload["first_name"],
      last_name: payload["last_name"],
      notes: payload["notes"],
      phone_e164: e164,
      email: pick_preferred(payload, "email"),
      first_seen_at: parse_dt(payload["first_seen_at"]) || now(),
      last_seen_at: parse_dt(payload["last_seen_at"]) || now(),
      last_synced_at: now()
    }
  end

  @doc """
  parse "Avery Chen" → `{"Avery", "Chen"}`. anything past the first
  space lands in last_name; an empty input clears both fields.
  """
  @spec split_name(String.t() | nil) :: {String.t() | nil, String.t() | nil}
  def split_name(raw) when is_binary(raw) do
    case raw |> String.trim() |> String.split(" ", parts: 2) do
      [""] -> {nil, nil}
      [first] -> {first, nil}
      [first, last] -> {first, String.trim(last)}
    end
  end

  def split_name(_), do: {nil, nil}

  @doc """
  salutation + first + last joined with spaces. empty string when the
  customer has no name on file (treat as "(no name)" at render).
  """
  @spec full_name(map()) :: String.t()
  def full_name(%{} = customer) do
    [
      Map.get(customer, :salutation),
      Map.get(customer, :first_name),
      Map.get(customer, :last_name)
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  @doc """
  thin wrapper over `reconcile_id/3` that pulls the preferred phone out
  of a resto-shaped payload.
  """
  def upsert_from_resto(org_id, %{"id" => _} = payload) when is_binary(org_id) do
    org = %Org{id: org_id, slug: "(reconcile)"}

    case pick_preferred(payload, "phone") do
      phone when is_binary(phone) ->
        reconcile_id(org, phone, payload)

      _ ->
        {:error, :missing_phone}
    end
  end

  def upsert_from_resto(_, _), do: {:error, :missing_id}

  @doc "used by the nightly reconciliation cron."
  def reconcile_from_resto(%Org{} = org) do
    case RestoClient.list_customers(org) do
      {:ok, customers} ->
        count =
          Enum.reduce(customers, 0, fn payload, acc ->
            phone = pick_preferred(payload, "phone")

            cond do
              is_binary(phone) and is_map(payload) ->
                case reconcile_id(org, phone, payload) do
                  {:ok, _} ->
                    acc + 1

                  {:error, reason} ->
                    Logger.warning(
                      "reconcile #{org.slug}: skipping #{inspect(payload["id"])} — #{inspect(reason)}"
                    )

                    acc
                end

              true ->
                acc
            end
          end)

        {:ok, count}

      {:error, _} = err ->
        err
    end
  end

  defp fallback_to_resto(%Org{} = org, e164) do
    case RestoClient.get_customer_by_phone(org, e164) do
      {:ok, payload} ->
        case reconcile_id(org, e164, payload) do
          {:ok, summary} -> {:ok, summary}
          {:error, reason} -> {:error, reason}
        end

      {:error, :not_found} ->
        :not_found

      {:error, _} = err ->
        err
    end
  end

  defp pick_preferred(%{"contacts" => contacts}, kind) when is_list(contacts) do
    case preferred_contact(contacts, kind) do
      nil -> nil
      contact -> contact["value"]
    end
  end

  defp pick_preferred(_, _), do: nil

  defp preferred_contact(contacts, kind) do
    of_kind = Enum.filter(contacts, &(&1["kind"] == kind))

    Enum.find(of_kind, &(&1["preferred"] == true)) ||
      List.first(of_kind)
  end

  defp parse_dt(nil), do: nil

  defp parse_dt(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> DateTime.truncate(dt, :second)
      {:error, _} -> nil
    end
  end

  defp normalize_or_error(phone) do
    case EllieAi.Phones.to_e164(phone) do
      {:ok, e164} -> {:ok, e164}
      {:error, reason} -> {:error, {:permanent, reason}}
    end
  end
end
