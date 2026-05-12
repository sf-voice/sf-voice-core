defmodule EllieAi.Groups.Group do
  @moduledoc """

  """

  use Ecto.Schema
  import Ecto.Changeset

  alias EllieAi.Orgs.Org

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @slug_regex ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/

  schema "groups" do
    field :slug, :string
    field :name, :string

    has_many :orgs, Org

    timestamps(type: :utc_datetime)
  end

  @creatable ~w(slug name)a
  @required ~w(slug name)a

  def changeset(group, attrs) do
    group
    |> cast(attrs, @creatable)
    |> validate_required(@required)
    |> validate_format(:slug, @slug_regex)
    |> unique_constraint(:slug)
  end
end
