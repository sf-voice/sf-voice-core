defmodule RestoBookingApp.Tables do
  @moduledoc """
  per-org floor-plan layout.

  every public function takes an `org_id`
  """

  import Ecto.Query

  alias RestoBookingApp.Repo
  alias RestoBookingApp.Tables.Table

  @doc "all tables for an org, ordered for consistent rendering."
  def all(org_id) when is_binary(org_id) do
    from(t in Table, where: t.org_id == ^org_id, order_by: [asc: t.sort_order, asc: t.slug])
    |> Repo.all()
  end

  @doc "list of valid table slugs for an org — used by the changeset."
  def slugs(org_id) when is_binary(org_id) do
    from(t in Table, where: t.org_id == ^org_id, select: t.slug)
    |> Repo.all()
  end

  @doc "look up a single table by slug within an org. nil if missing."
  def get(org_id, slug) when is_binary(org_id) and is_binary(slug) do
    Repo.get_by(Table, org_id: org_id, slug: slug)
  end

  @doc "total seat count across an org's floor plan."
  def seat_total(org_id) when is_binary(org_id) do
    from(t in Table, where: t.org_id == ^org_id, select: sum(t.seats))
    |> Repo.one()
    |> Kernel.||(0)
  end

  @doc "true if `slug` is a real table within `org_id`."
  def valid?(org_id, slug) when is_binary(org_id) and is_binary(slug) do
    from(t in Table, where: t.org_id == ^org_id and t.slug == ^slug, select: 1)
    |> Repo.one()
    |> is_integer()
  end

  @doc """
  upsert a single table by `(org_id, slug)`. used by seeds.exs to
  rebuild floor plans idempotently across deploys.
  """
  def upsert(org_id, attrs) when is_binary(org_id) and is_map(attrs) do
    attrs = Map.put(attrs, :org_id, org_id)
    slug = Map.fetch!(attrs, :slug)

    case get(org_id, slug) do
      nil ->
        %Table{}
        |> Table.changeset(attrs)
        |> Repo.insert()

      %Table{} = existing ->
        existing
        |> Table.changeset(attrs)
        |> Repo.update()
    end
  end
end
