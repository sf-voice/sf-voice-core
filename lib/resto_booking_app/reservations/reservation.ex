defmodule RestoBookingApp.Reservations.Reservation do
  @moduledoc """
  a single reservation: one table, one two-hour block, a name and an optional
  dietary note. cancel_token is generated server-side and returned to the
  caller so they (and only they) can mutate or delete the row later.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias RestoBookingApp.{Clock, Tables}

  # 30-minute slot grid, 2-hour booking length
  @slot_minutes 30
  @duration_minutes 120
  # opening hours, local time
  @open_hour 6
  # last bookable start = 20:00 so the 2h block ends at 22:00 close
  @last_start_hour 20

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "reservations" do
    field :cancel_token, :string
    field :table_id, :string
    field :starts_at, :utc_datetime
    field :ends_at, :utc_datetime
    field :name, :string
    field :dietary, :string
    field :notes, :string
    field :party_size, :integer

    timestamps(type: :utc_datetime)
  end

  @creatable_fields ~w(table_id starts_at name dietary notes party_size)a
  @required_fields ~w(table_id starts_at name party_size)a

  @doc "changeset used by both create and update — fills in ends_at + cancel_token as needed"
  def changeset(reservation, attrs) do
    reservation
    |> cast(attrs, @creatable_fields)
    |> validate_required(@required_fields)
    |> validate_table_id()
    |> validate_slot_alignment()
    |> validate_opening_hours()
    |> validate_party_size()
    |> put_ends_at()
    |> put_cancel_token()
  end

  defp validate_table_id(changeset) do
    validate_change(changeset, :table_id, fn :table_id, id ->
      if Tables.valid?(id), do: [], else: [table_id: "unknown table #{id}"]
    end)
  end

  defp validate_slot_alignment(changeset) do
    validate_change(changeset, :starts_at, fn :starts_at, %DateTime{} = dt ->
      cond do
        dt.minute not in [0, @slot_minutes] -> [starts_at: "must align to a 30-minute slot"]
        dt.second != 0 -> [starts_at: "must align to a 30-minute slot"]
        true -> []
      end
    end)
  end

  defp validate_opening_hours(changeset) do
    # the stored datetime is utc, but opening hours are local. shift before
    # comparing so a 21:00 PT booking isn't mistaken for 04:00 UTC.
    validate_change(changeset, :starts_at, fn :starts_at, %DateTime{} = dt ->
      %{hour: hour} = Clock.to_local(dt)

      if hour >= @open_hour and hour <= @last_start_hour do
        []
      else
        [starts_at: "must be between 06:00 and 20:00"]
      end
    end)
  end

  # party_size: must be at least 1, can't exceed the chosen table's capacity
  defp validate_party_size(changeset) do
    changeset
    |> validate_number(:party_size, greater_than: 0)
    |> validate_change(:party_size, fn :party_size, size ->
      table_id = get_field(changeset, :table_id)

      case table_id && Tables.get(table_id) do
        %{seats: seats} when size > seats ->
          [party_size: "is more than the table's #{seats} seats"]

        _ ->
          []
      end
    end)
  end

  defp put_ends_at(changeset) do
    case get_change(changeset, :starts_at) do
      %DateTime{} = starts ->
        put_change(changeset, :ends_at, DateTime.add(starts, @duration_minutes * 60, :second))

      _ ->
        changeset
    end
  end

  defp put_cancel_token(changeset) do
    case get_field(changeset, :cancel_token) do
      nil ->
        put_change(changeset, :cancel_token, generate_token())

      _existing ->
        # never rotate a token on update — it would lock the owner out of their own row
        changeset
    end
  end

  defp generate_token do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end

  @doc "useful constants for downstream code that needs to reason about slots"
  def slot_minutes, do: @slot_minutes
  def duration_minutes, do: @duration_minutes
  def open_hour, do: @open_hour
  def last_start_hour, do: @last_start_hour
end
