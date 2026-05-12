defmodule RestoBookingApp.Tables.Table do
  @moduledoc """
  one physical table in a restaurant's floor plan. previously a static
  module-level list; now a row in `tables`, scoped by `org_id`.

  `slug` is the short user-facing identifier shown in the UI ("T1", "T9")
  and stored on each reservation. unique within an org.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias RestoBookingApp.Orgs.Org

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "tables" do
    field :slug, :string
    field :seats, :integer
    field :shape, :string
    field :x, :integer
    field :y, :integer
    field :sort_order, :integer, default: 0

    belongs_to :org, Org

    timestamps(type: :utc_datetime)
  end

  @creatable ~w(org_id slug seats shape x y sort_order)a
  @required ~w(org_id slug seats shape x y)a
  @valid_shapes ~w(round square rect)

  def changeset(table, attrs) do
    table
    |> cast(attrs, @creatable)
    |> validate_required(@required)
    |> validate_number(:seats, greater_than: 0)
    |> validate_inclusion(:shape, @valid_shapes,
      message: "must be one of: #{Enum.join(@valid_shapes, ", ")}"
    )
    |> assoc_constraint(:org)
    |> unique_constraint([:org_id, :slug])
  end
end
