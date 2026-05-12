defmodule EllieAi.Utils do
  @moduledoc "small helpers shared across contexts."

  # convert top-level atom keys to strings. nested maps are left alone —
  # callers that need deep conversion should do that explicitly.
  @spec stringify_keys(map()) :: map()
  def stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end
end
