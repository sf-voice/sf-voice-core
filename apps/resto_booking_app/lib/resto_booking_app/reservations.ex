defmodule RestoBookingApp.Reservations do
  @moduledoc """
  reservations context. full crud over the single reservations table, plus
  the availability projection used by the live floor plan.

  every mutating function broadcasts on the `"floor_plan"` pubsub topic so
  the live view re-renders without a refresh.
  """

  import Ecto.Query

  alias RestoBookingApp.{Clock, Repo}
  alias RestoBookingApp.Reservations.Reservation
  alias Phoenix.PubSub

  @topic "floor_plan"
  @pubsub RestoBookingApp.PubSub

  # ── reads ────────────────────────────────────────────────────────────────

  @doc """
  list reservations. accepts `:date` to filter to a single calendar day in
  the restaurant's local timezone — handy for the floor plan and the api's
  `?date=` filter.
  """
  def list(opts \\ []) do
    Reservation
    |> filter_by_date(opts[:date])
    |> order_by([r], asc: r.starts_at)
    |> Repo.all()
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

  @doc "fetch one reservation by id, nil if missing"
  def get(id), do: Repo.get(Reservation, id)

  # ── writes ───────────────────────────────────────────────────────────────

  @doc """
  create a reservation. returns `{:ok, reservation}` or `{:error, changeset}`.

  the transaction runs in `:immediate` mode so the reserved write lock is
  taken at `BEGIN`, not lazily at first `INSERT`. with the default `:deferred`
  mode the overlap-check `SELECT` runs without any lock, and two parallel
  callers can both decide the slot is free before either tries to write —
  classic toctou. immediate mode forces them to serialise at `BEGIN`, so the
  loser sees the winner's row in its own select. paired with a db-level
  unique index on `(table_id, starts_at)` for defence in depth.
  """
  def create(attrs) do
    Repo.transaction(
      fn ->
        changeset = Reservation.changeset(%Reservation{}, attrs)

        with {:ok, prepared} <- apply_action_for_overlap_check(changeset),
             :ok <- check_no_overlap(prepared, exclude_id: nil),
             {:ok, reservation} <- Repo.insert(changeset) do
          broadcast({:reservation_created, reservation})
          reservation
        else
          {:error, %Ecto.Changeset{} = cs} -> Repo.rollback(cs)
          {:error, reason} -> Repo.rollback(reason)
        end
      end,
      mode: :immediate
    )
  end

  @doc """
  update an existing reservation. requires the cancel_token returned at
  creation. returns `{:ok, reservation}`, `{:error, :invalid_token}`,
  `{:error, :not_found}`, or `{:error, changeset}`.
  """
  def update(id, token, attrs) do
    case get(id) do
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

  # `:immediate` mode for the same reason as create/1 — moving a reservation's
  # time/table can race against a concurrent create on the destination slot.
  defp do_update(reservation, attrs) do
    Repo.transaction(
      fn ->
        changeset = Reservation.changeset(reservation, attrs)

        with {:ok, prepared} <- apply_action_for_overlap_check(changeset),
             :ok <- check_no_overlap(prepared, exclude_id: reservation.id),
             {:ok, updated} <- Repo.update(changeset) do
          broadcast({:reservation_updated, updated})
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
  delete a reservation. requires the cancel_token. returns `:ok`,
  `{:error, :invalid_token}`, or `{:error, :not_found}`.
  """
  def delete(id, token) do
    case get(id) do
      nil ->
        {:error, :not_found}

      %Reservation{cancel_token: actual} = reservation ->
        if secure_compare(actual, token) do
          {:ok, _} = Repo.delete(reservation)
          broadcast({:reservation_cancelled, reservation.id})
          :ok
        else
          {:error, :invalid_token}
        end
    end
  end

  # ── availability projection (live view fuel) ─────────────────────────────

  @doc """
  for a given date, group reservations by table id. returns a map keyed by
  every known table id (including ones with zero bookings) so the live view
  can iterate without worrying about missing keys.
  """
  def availability_for_date(%Date{} = date) do
    base = Map.new(RestoBookingApp.Tables.ids(), &{&1, []})

    # prepend while reducing (O(1) per step), then reverse once per table at
    # the end. preserves the asc-by-starts_at order that list/1 hands us.
    list(date: date)
    |> Enum.reduce(base, fn res, acc ->
      Map.update(acc, res.table_id, [res], &[res | &1])
    end)
    |> Map.new(fn {table_id, reservations} -> {table_id, Enum.reverse(reservations)} end)
  end

  # ── pubsub ───────────────────────────────────────────────────────────────

  @doc "subscribe to live floor plan updates — used by the live view on mount"
  def subscribe, do: PubSub.subscribe(@pubsub, @topic)

  defp broadcast(message), do: PubSub.broadcast(@pubsub, @topic, message)

  # ── helpers ──────────────────────────────────────────────────────────────

  # we run the changeset through `apply_action(:insert)` to compute ends_at
  # without hitting the db. that gives us a fully-validated struct to feed
  # the overlap query.
  defp apply_action_for_overlap_check(changeset) do
    case Ecto.Changeset.apply_action(changeset, :insert) do
      {:ok, struct} -> {:ok, struct}
      {:error, cs} -> {:error, cs}
    end
  end

  # overlap rule: two reservations on the same table overlap iff
  # `a.starts_at < b.ends_at AND a.ends_at > b.starts_at`. when updating, we
  # must exclude the row being updated from the search.
  defp check_no_overlap(%Reservation{} = res, exclude_id: exclude_id) do
    query =
      from r in Reservation,
        where:
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

  # constant-time string compare so a bad token can't be timing-side-channeled
  defp secure_compare(a, b) when is_binary(a) and is_binary(b) do
    Plug.Crypto.secure_compare(a, b)
  end

  defp secure_compare(_, _), do: false
end
