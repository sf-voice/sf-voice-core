defmodule EllieAi.Tools do
  @moduledoc """
  thin facade over `EllieAi.Tools.Catalog`. existed as its own list
  before the catalog landed; kept the public API for the admin UI
  but the source of truth is now `Catalog.all/0` (single registry,
  per project rule #22).

  each registered module implements the `EllieAi.Tools.Tool`
  behaviour (`name/0`, `description/0`, `parameters_schema/0`,
  `execute/2`).
  """

  alias EllieAi.Tools.{Catalog, Tool}

  @doc "every tool wired into the realtime session. delegates to Catalog."
  def list, do: Catalog.all()

  @doc """
  look up a registered tool module by its `name/0`. returns
  `{:ok, module}` or `{:error, :unknown_tool}`.
  """
  def find_by_name(name) when is_binary(name) do
    case Catalog.find(name) do
      nil -> {:error, :unknown_tool}
      module -> {:ok, module}
    end
  end

  @doc """
  shape every registered tool into the JSON definition the OpenAI
  Realtime session.update event expects.
  """
  def to_openai_definitions do
    Enum.map(list(), &Tool.to_openai/1)
  end
end
