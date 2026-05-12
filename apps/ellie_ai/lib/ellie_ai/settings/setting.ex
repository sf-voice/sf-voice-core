defmodule EllieAi.Settings.Setting do
  @moduledoc """

  """

  use Ecto.Schema
  import Ecto.Changeset

  alias EllieAi.Orgs.Org

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @value_types ~w(string int bool float json)

  schema "settings" do
    field :key, :string
    field :value, :string
    field :value_type, :string, default: "string"
    field :description, :string
    field :surfaced, :boolean, default: true

    belongs_to :org, Org

    timestamps(type: :utc_datetime)
  end

  @creatable ~w(org_id key value value_type description surfaced)a
  @required ~w(org_id key value_type)a

  def changeset(setting, attrs) do
    setting
    |> cast(attrs, @creatable)
    |> validate_required(@required)
    |> validate_inclusion(:value_type, @value_types,
      message: "must be one of: #{Enum.join(@value_types, ", ")}"
    )
    |> assoc_constraint(:org)
    |> unique_constraint([:org_id, :key])
  end

  @doc "decode a setting's string value using its value_type."
  def parsed(%__MODULE__{value: nil}), do: nil

  def parsed(%__MODULE__{value: v, value_type: "string"}), do: v
  def parsed(%__MODULE__{value: v, value_type: "int"}), do: String.to_integer(v)
  def parsed(%__MODULE__{value: v, value_type: "float"}), do: String.to_float(v)
  def parsed(%__MODULE__{value: "true", value_type: "bool"}), do: true
  def parsed(%__MODULE__{value: "false", value_type: "bool"}), do: false
  def parsed(%__MODULE__{value: v, value_type: "json"}), do: Jason.decode!(v)

  def value_types, do: @value_types
end
