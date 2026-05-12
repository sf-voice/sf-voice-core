defmodule RestoBookingApp.Contacts.Contact do
  @moduledoc """
  one channel of contact (phone, email, sms) for a customer. globally unique
  on (kind, value) so the same number can't belong to two customers — that's
  what makes ellie's by-phone lookup deterministic.

  `preferred` flags the contact a reservation defaults to when no override
  is pinned. exactly one preferred phone and one preferred email per
  customer is the intent; we enforce that at the context layer rather than
  with a partial unique index because sqlite's support is patchy.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias RestoBookingApp.Contacts.Constants
  alias RestoBookingApp.Customers.Customer
  alias RestoBookingApp.Orgs.Org
  alias RestoBookingApp.Validations

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "contacts" do
    field :kind, :string
    field :value, :string
    field :label, :string
    field :preferred, :boolean, default: false

    belongs_to :customer, Customer
    belongs_to :org, Org

    timestamps(type: :utc_datetime)
  end

  @creatable ~w(org_id customer_id kind value label preferred)a
  @required ~w(org_id customer_id kind value)a

  def changeset(contact, attrs) do
    contact
    |> cast(attrs, @creatable)
    |> validate_required(@required)
    |> validate_inclusion(:kind, Constants.kinds(),
      message: "must be one of: #{Enum.join(Constants.kinds(), ", ")}"
    )
    |> validate_value_for_kind()
    |> assoc_constraint(:customer)
    |> assoc_constraint(:org)
    |> unique_constraint([:kind, :value], name: :contacts_org_id_kind_value_index)
  end

  # validate the value against the rules of its kind. we only call this once
  # we know the kind is valid — otherwise the user gets two errors for one
  # mistake.
  defp validate_value_for_kind(changeset) do
    case get_field(changeset, :kind) do
      "phone" ->
        validate_format(changeset, :value, Validations.e164_regex(),
          message: "phone must be in E.164 format (e.g. +14155550100)"
        )

      "sms" ->
        validate_format(changeset, :value, Validations.e164_regex(),
          message: "sms must be in E.164 format (e.g. +14155550100)"
        )

      "email" ->
        validate_format(changeset, :value, Validations.email_regex(),
          message: "must look like an email address"
        )

      _ ->
        changeset
    end
  end
end
