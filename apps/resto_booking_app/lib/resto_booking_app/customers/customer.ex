defmodule RestoBookingApp.Customers.Customer do
  @moduledoc """
  a single guest. carries identity (names, salutation) and free-form notes.
  contact info (phone, email) lives in the linked `contacts` table — one
  row per channel, so a guest with two phone numbers is one customer with
  two contact rows.

  the natural key for reconciliation is the customer's preferred phone
  contact, looked up via `RestoBookingApp.Contacts.find_by_value/2` and
  walking up to the customer.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias RestoBookingApp.Contacts.Contact
  alias RestoBookingApp.Orgs.Org
  alias RestoBookingApp.Reservations.Reservation

  @salutations ~w(Mr Mrs Ms)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "customers" do
    field :salutation, :string
    field :first_name, :string
    field :last_name, :string
    field :notes, :string
    field :first_seen_at, :utc_datetime
    field :last_seen_at, :utc_datetime

    belongs_to :org, Org
    has_many :contacts, Contact
    has_many :reservations, Reservation

    timestamps(type: :utc_datetime)
  end

  # `id` is creatable because ellie mints the uuid first (on call landing,
  # local-only) and passes it through at booking time so both sides share
  # the same customer identity.
  @creatable ~w(id org_id salutation first_name last_name notes first_seen_at last_seen_at)a
  @required ~w(org_id)a

  @doc """
  changeset for create + update. nothing here is hard-required at the
  schema level: a phone-only first call may know nothing beyond the
  number, and the matching contact row carries that.
  """
  def changeset(customer, attrs) do
    customer
    |> cast(attrs, @creatable)
    |> validate_required(@required)
    |> validate_inclusion(:salutation, @salutations,
      message: "must be one of: #{Enum.join(@salutations, ", ")}"
    )
    |> assoc_constraint(:org)
  end

  @doc "convenience for staff UI: 'Mr Smith' style label, salutation optional"
  def display_name(%__MODULE__{salutation: s, first_name: f, last_name: l}) do
    [s, f, l]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
  end

  def salutations, do: @salutations
end
