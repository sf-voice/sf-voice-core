defmodule EllieAi.Settings do
  @moduledoc """
  per-org runtime configuration. read-through cache lives in the
  realtime session config; writes here take effect on the next call
  (or when the cache TTL expires — see EllieAi.Calls config helper).
  """

  import Ecto.Query

  alias EllieAi.Repo
  alias EllieAi.Settings.Setting

  # 30s read-through cache, keyed by {org_id, key}, lazily populated on
  # first miss. ttl is short enough that operator changes via /settings
  # land within a normal call without us needing to broadcast on writes.
  @cache_table :ellie_settings_cache
  @cache_ttl_ms 30_000

  defp ensure_cache do
    if :ets.whereis(@cache_table) == :undefined do
      try do
        :ets.new(@cache_table, [
          :named_table,
          :public,
          read_concurrency: true,
          write_concurrency: true
        ])
      rescue
        # lost the race — another process created the table between our
        # whereis check and :ets.new. fine, the table exists either way.
        ArgumentError -> :ok
      end
    end
  end

  defp cache_get(org_id, key) do
    ensure_cache()
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@cache_table, {org_id, key}) do
      [{_, value, expires_at}] when expires_at > now -> {:ok, value}
      _ -> :miss
    end
  end

  defp cache_put(org_id, key, value) do
    ensure_cache()
    expires_at = System.monotonic_time(:millisecond) + @cache_ttl_ms
    :ets.insert(@cache_table, {{org_id, key}, value, expires_at})
    value
  end

  defp cache_invalidate(org_id, key) do
    ensure_cache()
    :ets.delete(@cache_table, {org_id, key})
  end

  @doc "list all surfaced settings for an org. used by the staff /settings UI."
  def list(org_id, opts \\ []) when is_binary(org_id) do
    surfaced_only? = Keyword.get(opts, :surfaced_only, true)

    query = from(s in Setting, where: s.org_id == ^org_id, order_by: [asc: s.key])

    query =
      if surfaced_only? do
        from s in query, where: s.surfaced == true
      else
        query
      end

    Repo.all(query)
  end

  @doc "fetch one setting by key. returns the row, nil if missing."
  def get(org_id, key) when is_binary(org_id) and is_binary(key) do
    Repo.get_by(Setting, org_id: org_id, key: key)
  end

  @doc """
  fetch and parse one setting's value. returns the parsed value or
  `default` if the key isn't set. callers don't need to know the
  value_type — Setting.parsed/1 handles the cast.
  """
  def get_value(org_id, key, default \\ nil) do
    case cache_get(org_id, key) do
      {:ok, :sentinel_nil} ->
        default

      {:ok, cached} ->
        cached

      :miss ->
        value =
          case get(org_id, key) do
            nil -> nil
            %Setting{} = s -> Setting.parsed(s)
          end

        cache_put(org_id, key, if(is_nil(value), do: :sentinel_nil, else: value))
        if is_nil(value), do: default, else: value
    end
  end

  @doc "set or update a single key. uses `value_type` to validate the value."
  def put(org_id, key, value, opts \\ []) when is_binary(org_id) and is_binary(key) do
    value_type = Keyword.get(opts, :value_type, "string")
    description = Keyword.get(opts, :description)
    surfaced = Keyword.get(opts, :surfaced, true)

    attrs = %{
      org_id: org_id,
      key: key,
      value: stringify_value(value, value_type),
      value_type: value_type,
      description: description,
      surfaced: surfaced
    }

    # atomic upsert against the unique index on (org_id, key) — without this,
    # two concurrent put/4 calls for the same key race between the get and the
    # insert. on_conflict replaces the row, leaving id + inserted_at intact.
    result =
      %Setting{}
      |> Setting.changeset(attrs)
      |> Repo.insert(
        on_conflict: {:replace_all_except, [:id, :inserted_at]},
        conflict_target: [:org_id, :key]
      )

    cache_invalidate(org_id, key)
    result
  end

  @doc """
  bootstrap a key only if it doesn't already exist. used at app boot
  / during seeds to install defaults without overwriting operator
  customizations on subsequent runs.
  """
  def bootstrap(org_id, key, value, opts \\ []) when is_binary(org_id) and is_binary(key) do
    case get(org_id, key) do
      nil -> put(org_id, key, value, opts)
      %Setting{} = existing -> {:ok, existing}
    end
  end

  defp stringify_value(nil, _), do: nil
  defp stringify_value(v, "string") when is_binary(v), do: v
  defp stringify_value(v, "int") when is_integer(v), do: Integer.to_string(v)
  defp stringify_value(v, "float") when is_float(v), do: Float.to_string(v)
  defp stringify_value(true, "bool"), do: "true"
  defp stringify_value(false, "bool"), do: "false"
  defp stringify_value(v, "json"), do: Jason.encode!(v)
  defp stringify_value(v, _), do: to_string(v)
end
