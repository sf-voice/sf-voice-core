defmodule EllieAi.Menu do
  @moduledoc """
  per-org menu cache.
  """

  import Ecto.Query

  alias EllieAi.Menu.MenuItem
  alias EllieAi.Repo

  @doc "the entire menu for an org, keyed by service."
  def all(org_id) when is_binary(org_id) do
    base = Map.new(MenuItem.services(), &{&1, []})

    from(m in MenuItem,
      where: m.org_id == ^org_id,
      order_by: [asc: m.service, asc: m.sort_order, asc: m.name]
    )
    |> Repo.all()
    |> Enum.reduce(base, fn item, acc ->
      Map.update(acc, item.service, [item], &(&1 ++ [item]))
    end)
  end

  @doc "items for a specific service within an org."
  def for_service(org_id, service) when is_atom(service) do
    for_service(org_id, Atom.to_string(service))
  end

  def for_service(org_id, service) when is_binary(org_id) and is_binary(service) do
    from(m in MenuItem,
      where: m.org_id == ^org_id and m.service == ^service,
      order_by: [asc: m.sort_order, asc: m.name]
    )
    |> Repo.all()
  end

  @doc """
  upsert one menu item by `(org_id, service, name)`. used by the
  reconciliation cron when it pulls fresh data from resto.
  """
  def upsert_from_resto(org_id, payload) when is_binary(org_id) and is_map(payload) do
    service = Map.get(payload, "service") || Map.get(payload, :service)
    name = Map.get(payload, "name") || Map.get(payload, :name)

    if is_binary(service) and is_binary(name) do
      attrs = %{
        org_id: org_id,
        service: service,
        name: name,
        price_cents: Map.get(payload, "price_cents") || Map.get(payload, :price_cents),
        dietary: Map.get(payload, "dietary") || Map.get(payload, :dietary) || [],
        sort_order: Map.get(payload, "sort_order") || Map.get(payload, :sort_order) || 0,
        last_synced_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      # atomic upsert against the unique index on (org_id, service, name).
      %MenuItem{}
      |> MenuItem.changeset(attrs)
      |> Repo.insert(
        on_conflict: {:replace_all_except, [:id, :inserted_at]},
        conflict_target: [:org_id, :service, :name]
      )
    else
      {:error, :missing_keys}
    end
  end

  @doc """
  reconcile an org's full menu against a fresh payload from resto.
  """
  def reconcile(org_id, items) when is_binary(org_id) and is_list(items) do
    Repo.transaction(fn ->
      {upserted_keys, errors} =
        Enum.reduce(items, {[], 0}, fn item, {keys, err_count} ->
          case upsert_from_resto(org_id, item) do
            {:ok, %MenuItem{service: service, name: name}} ->
              {[{service, name} | keys], err_count}

            {:error, _} ->
              {keys, err_count + 1}
          end
        end)

      # destructive phase: only run when we have a complete, clean picture
      # of resto's menu.
      deleted =
        if errors > 0 do
          0
        else
          keep_keys = MapSet.new(upserted_keys)

          from(m in MenuItem, where: m.org_id == ^org_id, select: {m.id, m.service, m.name})
          |> Repo.all()
          |> Enum.reduce(0, fn {id, service, name}, count ->
            if MapSet.member?(keep_keys, {service, name}) do
              count
            else
              Repo.delete_all(from m in MenuItem, where: m.id == ^id)
              count + 1
            end
          end)
        end

      %{upserted: length(upserted_keys), deleted: deleted, errors: errors}
    end)
  end
end
