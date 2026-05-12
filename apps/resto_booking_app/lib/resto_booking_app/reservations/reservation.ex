defmodule RestoBookingApp.Reservations.Reservation do
  @moduledoc """
  a single reservation: one table, one two-hour block, linked to a customer
  via `customer_id`. cancel_token is generated server-side and returned to
  the caller so they (and only they) can mutate or delete the row later.

  guest contact details (name, tel, email, salutation) live on the
  customers table now — see RestoBookingApp.Customers.

  the restaurant is open 10:00–22:00 local time. bookings are 2 hours, so the
  last bookable start is 20:00 — anything later would run past close.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias RestoBookingApp.{Clock, Tables}
  alias RestoBookingApp.Contacts.Contact
  alias RestoBookingApp.Customers.Customer
  alias RestoBookingApp.Orgs.Org
  alias RestoBookingApp.Reservations.Constants

  @duration_minutes 120

  @open_minutes 10 * 60

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "reservations" do
    field :cancel_token, :string
    field :table_id, :string
    field :starts_at, :utc_datetime
    field :ends_at, :utc_datetime

    field :party_size, :integer
    field :special_requests, :string
    field :remarks, :string

    belongs_to :customer, Customer
    belongs_to :contact, Contact
    belongs_to :org, Org

    timestamps(type: :utc_datetime)
  end

  @creatable_fields ~w(org_id table_id starts_at customer_id contact_id party_size special_requests remarks)a
  @required_fields ~w(org_id table_id starts_at customer_id party_size)a

  @doc "changeset used by both create and update — fills in ends_at + cancel_token as needed"
  def changeset(reservation, attrs) do
    reservation
    |> cast(attrs, @creatable_fields)
    |> validate_required(@required_fields)
    |> validate_table_id()
    |> validate_slot_alignment()
    |> validate_opening_hours()
    |> validate_party_size()
    |> assoc_constraint(:customer)
    |> assoc_constraint(:contact)
    |> assoc_constraint(:org)
    |> put_ends_at()
    |> put_cancel_token()
    |> unique_constraint(:starts_at, name: :reservations_org_id_table_id_starts_at_index)
  end

  defp validate_table_id(changeset) do
    validate_change(changeset, :table_id, fn :table_id, id ->
      case get_field(changeset, :org_id) do
        nil ->
          []

        org_id ->
          if Tables.valid?(org_id, id), do: [], else: [table_id: "unknown table #{id}"]
      end
    end)
  end

  defp validate_slot_alignment(changeset) do
    validate_change(changeset, :starts_at, fn :starts_at, %DateTime{} = dt ->
      cond do
        dt.minute not in [0, Constants.slot_minutes()] ->
          [starts_at: "must align to a 30-minute slot"]

        dt.second != 0 ->
          [starts_at: "must align to a 30-minute slot"]

        true ->
          []
      end
    end)
  end

  defp validate_opening_hours(changeset) do
    validate_change(changeset, :starts_at, fn :starts_at, %DateTime{} = dt ->
      %{hour: h, minute: m} = Clock.to_local(dt)
      mins = h * 60 + m

      if mins >= @open_minutes and mins <= Constants.last_start_minutes() do
        []
      else
        [starts_at: "must be between 10:00 and 20:00"]
      end
    end)
  end

  defp validate_party_size(changeset) do
    changeset
    |> validate_number(:party_size, greater_than: 0)
    |> validate_change(:party_size, fn :party_size, size ->
      table_id = get_field(changeset, :table_id)
      org_id = get_field(changeset, :org_id)

      case org_id && table_id && Tables.get(org_id, table_id) do
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
        changeset
    end
  end

  defp generate_token do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end

  @doc "useful constants for downstream code that needs to reason about slots"
  def duration_minutes, do: @duration_minutes
  def open_minutes, do: @open_minutes
end
