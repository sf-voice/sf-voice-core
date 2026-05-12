defmodule RestoBookingApp.MenuItems.MenuItem do
  @moduledoc """
  one item on a restaurant's menu. previously a static map; now a row
  in `menu_items` scoped by `org_id`. ellie polls `/api/menu` every 5
  minutes to mirror this into its own read cache.

  `dietary` is stored as a comma-separated string for sqlite simplicity
  ("vegan,gluten_free"). the changeset normalizes input (list or csv)
  to that shape; readers split it into a list when emitted as JSON.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias RestoBookingApp.Menu.Constants
  alias RestoBookingApp.Orgs.Org

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  # services list lives in `Constants` (shared with the menu context).
  @dietary_tags ~w(vegan vegetarian gluten_free nut_free dairy_free)

  schema "menu_items" do
    field :service, :string
    field :name, :string
    field :price_cents, :integer
    field :dietary, :string, default: ""
    field :sort_order, :integer, default: 0

    belongs_to :org, Org

    timestamps(type: :utc_datetime)
  end

  @creatable ~w(org_id service name price_cents dietary sort_order)a
  @required ~w(org_id service name price_cents)a

  def changeset(item, attrs) do
    # normalize dietary BEFORE cast — it's a string column but callers
    # frequently pass a list. cast/3 would reject the list outright.
    item
    |> cast(normalize_input(attrs), @creatable)
    |> validate_required(@required)
    |> validate_inclusion(:service, Constants.services(),
      message: "must be one of: #{Enum.join(Constants.services(), ", ")}"
    )
    |> validate_number(:price_cents, greater_than: 0)
    |> assoc_constraint(:org)
  end

  @doc "dietary tags as an atom list — the json view's preferred shape"
  def dietary_list(%__MODULE__{dietary: ""}), do: []
  def dietary_list(%__MODULE__{dietary: nil}), do: []

  def dietary_list(%__MODULE__{dietary: csv}) when is_binary(csv) do
    csv |> String.split(",", trim: true) |> Enum.map(&String.to_atom/1)
  end

  def dietary_tags, do: @dietary_tags

  # accept either a list (`[:vegan, :gluten_free]`) or a string. always
  # store as comma-separated string in the column.
  defp normalize_input(attrs) when is_map(attrs) do
    case Map.get(attrs, :dietary) || Map.get(attrs, "dietary") do
      tags when is_list(tags) ->
        csv =
          tags
          |> Enum.map(&to_string/1)
          |> Enum.reject(&(&1 == ""))
          |> Enum.join(",")

        attrs |> Map.delete("dietary") |> Map.put(:dietary, csv)

      _ ->
        attrs
    end
  end

  defp normalize_input(other), do: other
end
