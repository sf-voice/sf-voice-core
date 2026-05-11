defmodule RestoBookingApp.Menu do


  import Ecto.Query

  alias RestoBookingApp.Menu.Constants
  alias RestoBookingApp.MenuItems.MenuItem
  alias RestoBookingApp.Repo

  @doc """
  the entire menu for an org, key by service
  """
  def all(org_id) when is_binary(org_id) do
    base = Map.new(Constants.services(), &{String.to_atom(&1), []})

    from(m in MenuItem,
      where: m.org_id == ^org_id,
      order_by: [asc: m.service, asc: m.sort_order, asc: m.name]
    )
    |> Repo.all()
    |> Enum.reduce(base, fn item, acc ->
      key = String.to_atom(item.service)
      Map.update(acc, key, [item], &(&1 ++ [item]))
    end)
  end

  @doc "items for a specific service within an org."
  def for_service(org_id, service) when is_binary(org_id) and is_atom(service) do
    for_service(org_id, Atom.to_string(service))
  end

  def for_service(org_id, service) when is_binary(org_id) and is_binary(service) do
    from(m in MenuItem,
      where: m.org_id == ^org_id and m.service == ^service,
      order_by: [asc: m.sort_order, asc: m.name]
    )
    |> Repo.all()
  end

  @doc "list of services we offer (constant — currently breakfast/lunch/dinner)."
  def services, do: Constants.services() |> Enum.map(&String.to_atom/1)

  @doc "upsert one menu item by `(org_id, service, name)`. used by seeds.exs."
  def upsert(org_id, attrs) when is_binary(org_id) and is_map(attrs) do
    attrs = Map.put(attrs, :org_id, org_id)
    service = Map.fetch!(attrs, :service) |> to_string()
    name = Map.fetch!(attrs, :name)

    existing =
      Repo.one(
        from m in MenuItem,
          where: m.org_id == ^org_id and m.service == ^service and m.name == ^name
      )

    case existing do
      nil ->
        %MenuItem{}
        |> MenuItem.changeset(attrs)
        |> Repo.insert()

      %MenuItem{} = item ->
        item
        |> MenuItem.changeset(attrs)
        |> Repo.update()
    end
  end
end
