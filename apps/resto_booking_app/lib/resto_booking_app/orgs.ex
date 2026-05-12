defmodule RestoBookingApp.Orgs do
  @moduledoc """
  orgs context. small surface — orgs are slow-changing, mostly read-only
  outside of seeds.
  """

  alias RestoBookingApp.Orgs.Org
  alias RestoBookingApp.Repo

  @doc "list all orgs."
  def list, do: Repo.all(Org)

  @doc "fetch an org by id, nil if not found."
  def get(id), do: Repo.get(Org, id)

  @doc "fetch an org by slug, nil if not found. used by the OrgScope plug."
  def get_by_slug(slug) when is_binary(slug), do: Repo.get_by(Org, slug: slug)

  @doc "create an org. used by seeds.exs and admin tools."
  def create(attrs) do
    %Org{}
    |> Org.changeset(attrs)
    |> Repo.insert()
  end

  @doc "find or create by slug — idempotent for seeds."
  def upsert_by_slug(slug, attrs) when is_binary(slug) do
    attrs = Map.put(attrs, :slug, slug)

    case get_by_slug(slug) do
      nil ->
        create(attrs)

      %Org{} = existing ->
        existing
        |> Org.changeset(attrs)
        |> Repo.update()
    end
  end
end
