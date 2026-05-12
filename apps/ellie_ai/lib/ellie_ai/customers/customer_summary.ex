defmodule EllieAi.Customers.CustomerSummary do
  @moduledoc """
  `id` is shared with resto's `customers.id`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias EllieAi.Orgs.Org

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "customer_summary" do
    field :salutation, :string
    field :first_name, :string
    field :last_name, :string
    field :notes, :string
    field :phone_e164, :string
    field :email, :string
    field :first_seen_at, :utc_datetime
    field :last_seen_at, :utc_datetime
    field :last_synced_at, :utc_datetime

    belongs_to :org, Org

    timestamps(type: :utc_datetime)
  end

  @creatable ~w(id org_id salutation first_name last_name notes phone_e164
                email first_seen_at last_seen_at last_synced_at)a
  @required ~w(org_id last_synced_at)a

  def changeset(summary, attrs) do
    summary
    |> cast(attrs, @creatable)
    |> validate_required(@required)
    |> assoc_constraint(:org)
    |> unique_constraint([:org_id, :phone_e164])
  end

  @doc "convenience for ellie's staff UI: 'Mr Smith' style label."
  def display_name(%__MODULE__{salutation: s, first_name: f, last_name: l}) do
    [s, f, l]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
  end
end
