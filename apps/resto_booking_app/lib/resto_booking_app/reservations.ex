defmodule RestoBookingApp.Reservations do
  @moduledoc """
  reservations context. multi-tenant: every public function takes
  `org_id` as its first argument so cross-org reads/writes are
  impossible. controllers resolve `org_id` from the path
  (`/api/orgs/:org_slug/...`) via the `OrgScope` plug.

  every mutating function broadcasts on the `"floor_plan:<org_id>"`
  pubsub topic so the live view re-renders without a refresh — note
  the topic is per-org so different orgs don't interfere.
  """

  import Ecto.Query

  alias RestoBookingApp.{Clock, Contacts, Repo, Tables}
  alias RestoBookingApp.Reservations.Reservation
  alias Phoenix.PubSub

  @pubsub RestoBookingApp.PubSub

  # ── reads ────────────────────────────────────────────────────────────────

  @doc """
  list reservations within an org. accepts `:date`, `:customer_id`, and
  `:preload`.
  """
  def list(org_id, opts \\ []) when is_binary(org_id) do
    Reservation
    |> scope_to_org(org_id)
    |> filter_by_date(opts[:date])
    |> filter_by_customer(opts[:customer_id])
    |> order_by([r], asc: r.starts_at)
    |> Repo.all()
    |> maybe_preload(opts[:preload])
  end

  defp scope_to_org(query, org_id) do
    from r in query, where: r.org_id == ^org_id
  end

  defp filter_by_date(query, nil), do: query

  defp filter_by_date(query, %Date{} = date) do
    # build the day window in local time, then convert to utc for the query.
    # this keeps a "saturday in SF" actually saturday-in-SF, not the slice of
    # saturday that happens to fall in the utc calendar day.
    day_start = Clock.local_to_utc(date, ~T[00:00:00])
    day_end = DateTime.add(day_start, 24 * 60 * 60, :second)
    from r in query, where: r.starts_at >= ^day_start and r.starts_at < ^day_end
  end

  defp filter_by_customer(query, nil), do: query

  defp filter_by_customer(query, customer_id) when is_binary(customer_id) do
    from r in query, where: r.customer_id == ^customer_id
  end

  defp maybe_preload(nil, _), do: nil
  defp maybe_preload(reservations, nil), do: reservations
  defp maybe_preload(reservations, preload), do: Repo.preload(reservations, preload)

  @doc """
  fetch one reservation by id, scoped to org. nil if missing or
  belonging to another org. accepts `:preload`.
  """
  def get(org_id, id, opts \\ []) when is_binary(org_id) do
    Reservation
    |> scope_to_org(org_id)
    |> Repo.get(id)
    |> maybe_preload(opts[:preload])
  end

  # ── writes ───────────────────────────────────────────────────────────────

  @doc """
  create a reservation. attrs must include `org_id`.

  two shapes are accepted:

    * legacy — `customer_id` points at an existing customer row. used by
      the resto-side booking form and existing tests.
    * inline — `customer: %{id, phone, first_name, last_name, ...}`.
      ellie's path: resto upserts the customer (find_or_create_for_phone
      keyed on phone) inside the same transaction, then inserts the
      reservation. atomic — a failed booking never leaves a half-created
      customer behind.

  transaction runs in `:immediate` mode for the same toctou reasons as before.
  """
  def create(attrs) do
    Repo.transaction(
      fn ->
        with {:ok, attrs} <- maybe_upsert_customer(attrs),
             changeset = Reservation.changeset(%Reservation{}, attrs),
             {:ok, prepared} <- apply_action_for_overlap_check(changeset),
             :ok <- check_no_overlap(prepared, exclude_id: nil),
             {:ok, reservation} <- Repo.insert(changeset) do
          broadcast(reservation.org_id, {:reservation_created, reservation})
          reservation
        else
          {:error, %Ecto.Changeset{} = cs} -> Repo.rollback(cs)
          {:error, reason} -> Repo.rollback(reason)
        end
      end,
      mode: :immediate
    )
  end

  # if `customer` is present in attrs, upsert it via Contacts and rewrite
  # attrs to carry the resulting `customer_id`. existing reservations
  # that already pass `customer_id` skip this entirely.
  defp maybe_upsert_customer(%{"customer" => %{} = customer} = attrs),
    do: do_upsert_customer(attrs, customer)

  defp maybe_upsert_customer(%{customer: %{} = customer} = attrs),
    do: do_upsert_customer(attrs, customer)

  defp maybe_upsert_customer(attrs), do: {:ok, attrs}

  defp do_upsert_customer(attrs, customer) do
    org_id = attrs["org_id"] || attrs[:org_id]
    phone = customer["phone"] || customer[:phone]

    if is_binary(org_id) and is_binary(phone) and phone != "" do
      case Contacts.find_or_create_for_phone(org_id, phone, customer) do
        {:ok, %{id: id}} ->
          rewritten =
            attrs
            |> Map.drop(["customer", :customer])
            |> Map.put("customer_id", id)

          {:ok, rewritten}

        {:error, _} = err ->
          err
      end
    else
      {:error, {:invalid_customer, "customer.phone and org_id are required"}}
    end
  end

  @doc """
  update an existing reservation. `org_id` scopes the lookup;
  `cancel_token` proves ownership. returns the same shape as before
  plus `:not_found` when the id belongs to another org.
  """
  def update(org_id, id, token, attrs) do
    case get(org_id, id) do
      nil ->
        {:error, :not_found}

      %Reservation{cancel_token: actual} = reservation ->
        if secure_compare(actual, token) do
          do_update(reservation, attrs)
        else
          {:error, :invalid_token}
        end
    end
  end

  defp do_update(reservation, attrs) do
    Repo.transaction(
      fn ->
        changeset = Reservation.changeset(reservation, attrs)

        with {:ok, prepared} <- apply_action_for_overlap_check(changeset),
             :ok <- check_no_overlap(prepared, exclude_id: reservation.id),
             {:ok, updated} <- Repo.update(changeset) do
          broadcast(updated.org_id, {:reservation_updated, updated})
          updated
        else
          {:error, %Ecto.Changeset{} = cs} -> Repo.rollback(cs)
          {:error, reason} -> Repo.rollback(reason)
        end
      end,
      mode: :immediate
    )
  end

  @doc """
  delete a reservation. `org_id` scopes the lookup; `cancel_token`
  proves ownership.
  """
  def delete(org_id, id, token) do
    case get(org_id, id) do
      nil ->
        {:error, :not_found}

      %Reservation{cancel_token: actual} = reservation ->
        if secure_compare(actual, token) do
          {:ok, _} = Repo.delete(reservation)
          broadcast(reservation.org_id, {:reservation_cancelled, reservation.id})
          :ok
        else
          {:error, :invalid_token}
        end
    end
  end

  # ── availability projection (live view fuel) ─────────────────────────────

  @doc """
  for a given date and org, group reservations by table id. returns
  a map keyed by every known table id (including ones with zero
  bookings) so the live view can iterate without worrying about
  missing keys.
  """
  def availability_for_date(org_id, %Date{} = date) when is_binary(org_id) do
    table_slugs = Tables.slugs(org_id)
    base = Map.new(table_slugs, &{&1, []})

    org_id
    |> list(date: date, preload: [:customer, :contact])
    |> Enum.reduce(base, fn res, acc ->
      Map.update(acc, res.table_id, [res], &[res | &1])
    end)
    |> Map.new(fn {table_id, reservations} -> {table_id, Enum.reverse(reservations)} end)
  end

  # ── pubsub ───────────────────────────────────────────────────────────────

  @doc """
  subscribe to a single org's floor plan updates — used by the live
  view on mount. each org has its own topic so live views don't
  receive cross-org broadcasts.
  """
  def subscribe(org_id) when is_binary(org_id) do
    PubSub.subscribe(@pubsub, topic(org_id))
  end

  defp broadcast(org_id, message) when is_binary(org_id) do
    PubSub.broadcast(@pubsub, topic(org_id), message)
  end

  defp topic(org_id), do: "floor_plan:" <> org_id

  # ── helpers ──────────────────────────────────────────────────────────────

  defp apply_action_for_overlap_check(changeset) do
    case Ecto.Changeset.apply_action(changeset, :insert) do
      {:ok, struct} -> {:ok, struct}
      {:error, cs} -> {:error, cs}
    end
  end

  # overlap rule: two reservations on the same table within the same org
  # overlap iff `a.starts_at < b.ends_at AND a.ends_at > b.starts_at`.
  defp check_no_overlap(%Reservation{} = res, exclude_id: exclude_id) do
    query =
      from r in Reservation,
        where:
          r.org_id == ^res.org_id and
            r.table_id == ^res.table_id and
            r.starts_at < ^res.ends_at and
            r.ends_at > ^res.starts_at

    query =
      case exclude_id do
        nil -> query
        id -> from r in query, where: r.id != ^id
      end

    case Repo.exists?(query) do
      false ->
        :ok

      true ->
        cs =
          %Reservation{}
          |> Ecto.Changeset.change()
          |> Ecto.Changeset.add_error(:starts_at, "table is already booked for this time slot")

        {:error, %{cs | action: :insert}}
    end
  end

  defp secure_compare(a, b) when is_binary(a) and is_binary(b) do
    Plug.Crypto.secure_compare(a, b)
  end

  defp secure_compare(_, _), do: false
end
