defmodule RestoBookingApp.Reservations.Reservation do
  @moduledoc """
  a single reservation: one table, one two-hour block, the guest's contact
  details, plus optional special requests and remarks. cancel_token is
  generated server-side and returned to the caller so they (and only they)
  can mutate or delete the row later.

  the restaurant is open 10:00–22:00 local time. bookings are 2 hours, so the
  last bookable start is 20:00 — anything later would run past close.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias RestoBookingApp.{Clock, Tables}

  # 30-minute slot grid, 2-hour booking length
  @slot_minutes 30
  @duration_minutes 120

  # opening hours (local time) expressed in minutes-since-midnight so the
  # check covers the half-hour boundary cleanly: 20:30 ends at 22:30, so it's
  # rejected even though hour 20 is "in range".
  @open_minutes 10 * 60
  @last_start_minutes 20 * 60

  # salutations are constrained to the form's three options. unset is allowed.
  @salutations ~w(Mr Mrs Ms)

  # cheap-and-cheerful email shape check. we don't pretend to validate rfc 5321 —
  # this just rejects the obviously-broken stuff so the form gives quick feedback.
  @email_regex ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "reservations" do
    field :cancel_token, :string
    field :table_id, :string
    field :starts_at, :utc_datetime
    field :ends_at, :utc_datetime

    field :salutation, :string
    field :first_name, :string
    field :last_name, :string
    field :tel, :string
    field :email, :string
    field :party_size, :integer
    field :special_requests, :string
    field :remarks, :string

    timestamps(type: :utc_datetime)
  end

  @creatable_fields ~w(
    table_id starts_at salutation first_name last_name tel email
    party_size special_requests remarks
  )a
  @required_fields ~w(table_id starts_at first_name last_name tel email party_size)a

  @doc "changeset used by both create and update — fills in ends_at + cancel_token as needed"
  def changeset(reservation, attrs) do
    reservation
    |> cast(attrs, @creatable_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:salutation, @salutations,
      message: "must be one of: #{Enum.join(@salutations, ", ")}"
    )
    |> validate_format(:email, @email_regex, message: "must look like an email address")
    |> validate_table_id()
    |> validate_slot_alignment()
    |> validate_opening_hours()
    |> validate_party_size()
    |> put_ends_at()
    |> put_cancel_token()
    # backstop for the application-level overlap check. if two callers race
    # past the in-process check, the db's unique index rejects the second
    # insert and ecto translates the constraint violation into a normal
    # changeset error instead of a 500.
    |> unique_constraint(:starts_at, name: :reservations_table_id_starts_at_index)
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

  # the stored datetime is utc, but opening hours are local. shift before
  # comparing so a 21:00 PT booking isn't mistaken for 04:00 UTC.
  defp validate_opening_hours(changeset) do
    validate_change(changeset, :starts_at, fn :starts_at, %DateTime{} = dt ->
      %{hour: h, minute: m} = Clock.to_local(dt)
      mins = h * 60 + m

      if mins >= @open_minutes and mins <= @last_start_minutes do
        []
      else
        [starts_at: "must be between 10:00 and 20:00"]
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
  def open_minutes, do: @open_minutes
  def last_start_minutes, do: @last_start_minutes
  def salutations, do: @salutations

  @doc "convenience for the floor plan: 'Avery Chen' (no salutation)"
  def display_name(%__MODULE__{first_name: f, last_name: l}) do
    [f, l] |> Enum.reject(&(&1 in [nil, ""])) |> Enum.join(" ")
  end

  @doc "convenience for confirmation surfaces: 'Mr Avery Chen' (with salutation when present)"
  def full_name(%__MODULE__{salutation: s} = res) do
    [s, display_name(res)] |> Enum.reject(&(&1 in [nil, ""])) |> Enum.join(" ")
  end
end
