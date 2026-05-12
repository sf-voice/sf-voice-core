defmodule EllieAi.Prompts.Prompt do
  @moduledoc """
  body is EEx-templated.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias EllieAi.Orgs.Org

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "prompts" do
    field :name, :string
    field :body, :string
    field :version, :integer, default: 1
    field :active, :boolean, default: false
    field :created_by, :string

    belongs_to :org, Org

    timestamps(type: :utc_datetime)
  end

  @creatable ~w(org_id name body version active created_by)a
  @required ~w(org_id name body version)a

  def changeset(prompt, attrs) do
    prompt
    |> cast(attrs, @creatable)
    |> validate_required(@required)
    |> validate_number(:version, greater_than: 0)
    |> assoc_constraint(:org)
    |> unique_constraint([:org_id, :version])
  end
end
