defmodule RestoBookingApp.Orgs.Org do
  @moduledoc """
  one restaurant location. multi-tenancy is per-org: customers,
  reservations, tables, and menu items all belong to exactly one org and
  never cross over.

  slug is the natural key used in URLs and api paths
  (`/api/orgs/:org_slug/...`). time_zone is IANA so dynamic date facts
  in ellie's system prompt localize correctly per restaurant.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias RestoBookingApp.Contacts.Contact
  alias RestoBookingApp.Customers.Customer
  alias RestoBookingApp.MenuItems.MenuItem
  alias RestoBookingApp.Reservations.Reservation
  alias RestoBookingApp.Tables.Table

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @slug_regex ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/

  schema "orgs" do
    field :slug, :string
    field :name, :string
    field :location, :string
    field :time_zone, :string, default: "America/Los_Angeles"

    has_many :tables, Table
    has_many :menu_items, MenuItem
    has_many :customers, Customer
    has_many :contacts, Contact
    has_many :reservations, Reservation

    timestamps(type: :utc_datetime)
  end

  @creatable ~w(slug name location time_zone)a
  @required ~w(slug name time_zone)a

  def changeset(org, attrs) do
    org
    |> cast(attrs, @creatable)
    |> validate_required(@required)
    |> validate_format(:slug, @slug_regex,
      message: "must be lowercase letters, numbers, and dashes (e.g. seasons-sf)"
    )
    |> unique_constraint(:slug)
  end
end
