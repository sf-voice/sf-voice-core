defmodule EllieAi.Groups do
  @moduledoc """
  """

  alias EllieAi.Groups.Group
  alias EllieAi.Repo

  def list, do: Repo.all(Group)
  def get(id), do: Repo.get(Group, id)
  def get_by_slug(slug), do: Repo.get_by(Group, slug: slug)

  def create(attrs) do
    %Group{}
    |> Group.changeset(attrs)
    |> Repo.insert()
  end

  def upsert_by_slug(slug, attrs) when is_binary(slug) do
    attrs = Map.put(attrs, :slug, slug)

    case get_by_slug(slug) do
      nil -> create(attrs)
      %Group{} = g -> g |> Group.changeset(attrs) |> Repo.update()
    end
  end
end
