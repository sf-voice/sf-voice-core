defmodule EllieAi.Menu.MenuItem do
  @moduledoc """

  """

  use Ecto.Schema
  import Ecto.Changeset

  alias EllieAi.Orgs.Org

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @services ~w(breakfast lunch dinner)

  schema "menu_items" do
    field :service, :string
    field :name, :string
    field :price_cents, :integer
    field :dietary, :string, default: ""
    field :sort_order, :integer, default: 0
    field :last_synced_at, :utc_datetime

    belongs_to :org, Org

    timestamps(type: :utc_datetime)
  end

  @creatable ~w(org_id service name price_cents dietary sort_order last_synced_at)a
  @required ~w(org_id service name price_cents last_synced_at)a

  def changeset(item, attrs) do
    item
    |> cast(normalize_input(attrs), @creatable)
    |> validate_required(@required)
    |> validate_inclusion(:service, @services)
    |> validate_number(:price_cents, greater_than: 0)
    |> assoc_constraint(:org)
  end

  def dietary_list(%__MODULE__{dietary: ""}), do: []
  def dietary_list(%__MODULE__{dietary: nil}), do: []

  def dietary_list(%__MODULE__{dietary: csv}) when is_binary(csv) do
    csv |> String.split(",", trim: true) |> Enum.map(&String.to_atom/1)
  end

  def services, do: @services

  defp normalize_input(attrs) when is_map(attrs) do
    case Map.get(attrs, :dietary) || Map.get(attrs, "dietary") do
      tags when is_list(tags) ->
        csv = tags |> Enum.map(&to_string/1) |> Enum.reject(&(&1 == "")) |> Enum.join(",")
        attrs |> Map.delete("dietary") |> Map.put(:dietary, csv)

      _ ->
        attrs
    end
  end

  defp normalize_input(other), do: other
end
