defmodule EllieAi.Settings do
  @moduledoc """
  """

  import Ecto.Query

  alias EllieAi.Repo
  alias EllieAi.Settings.Setting

  # 30s read-through cache, keyed by {org_id, key}, lazily populated on
  # first miss. table itself is created in EllieAi.Application.start/2 so
  # it's owned by the application controller (effectively immortal) — if a
  # plug worker owned it the cache would die with each request.
  @cache_table :ellie_settings_cache
  @cache_ttl_ms 30_000

  defp cache_get(org_id, key) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@cache_table, {org_id, key}) do
      [{_, value, expires_at}] when expires_at > now -> {:ok, value}
      _ -> :miss
    end
  end

  defp cache_put(org_id, key, value) do
    expires_at = System.monotonic_time(:millisecond) + @cache_ttl_ms
    :ets.insert(@cache_table, {{org_id, key}, value, expires_at})
    value
  end

  defp cache_invalidate(org_id, key) do
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

    case encode_value(value, value_type) do
      {:ok, encoded} ->
        attrs = %{
          org_id: org_id,
          key: key,
          value: encoded,
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

      {:error, reason} ->
        {:error, encode_error_changeset(org_id, key, value_type, description, surfaced, reason)}
    end
  end

  @doc """
  bootstrap a key only if it doesn't already exist. used at app boot
  / during seeds to install defaults without overwriting operator
  customizations on subsequent runs.
  """
  def bootstrap(org_id, key, value, opts \\ []) when is_binary(org_id) and is_binary(key) do
    value_type = Keyword.get(opts, :value_type, "string")
    description = Keyword.get(opts, :description)
    surfaced = Keyword.get(opts, :surfaced, true)

    case encode_value(value, value_type) do
      {:ok, encoded} ->
        attrs = %{
          org_id: org_id,
          key: key,
          value: encoded,
          value_type: value_type,
          description: description,
          surfaced: surfaced
        }

        # atomic insert-if-absent against the unique index on (org_id, key). unlike
        # put/4 which uses replace_all_except, bootstrap must preserve any existing
        # row so operator customizations survive subsequent boots/seeds. the old
        # get/2 -> put/4 path raced: two concurrent bootstrap calls (or bootstrap vs
        # put) could both see nil and the second would clobber the first.
        result =
          %Setting{}
          |> Setting.changeset(attrs)
          |> Repo.insert(
            on_conflict: :nothing,
            conflict_target: [:org_id, :key]
          )

        case result do
          {:ok, %Setting{id: nil}} ->
            # conflict — row already existed. return whatever's in the db; never
            # blindly overwrite a concurrent write.
            {:ok, get(org_id, key)}

          {:ok, %Setting{}} = ok ->
            cache_invalidate(org_id, key)
            ok

          {:error, _} = err ->
            err
        end

      {:error, reason} ->
        {:error, encode_error_changeset(org_id, key, value_type, description, surfaced, reason)}
    end
  end

  # only the "json" branch can fail (bad input → jason error). every other
  # branch is total, so we wrap them in {:ok, _} to keep one return shape.
  defp encode_value(nil, _), do: {:ok, nil}
  defp encode_value(v, "json"), do: Jason.encode(v)
  defp encode_value(v, type), do: {:ok, stringify_value(v, type)}

  defp stringify_value(v, "string") when is_binary(v), do: v
  defp stringify_value(v, "int") when is_integer(v), do: Integer.to_string(v)
  defp stringify_value(v, "float") when is_float(v), do: Float.to_string(v)
  defp stringify_value(true, "bool"), do: "true"
  defp stringify_value(false, "bool"), do: "false"
  defp stringify_value(v, _), do: to_string(v)

  # surface encode failures through the same changeset contract callers
  # already handle, instead of letting a raise escape from put/bootstrap.
  defp encode_error_changeset(org_id, key, value_type, description, surfaced, reason) do
    %Setting{}
    |> Setting.changeset(%{
      org_id: org_id,
      key: key,
      value_type: value_type,
      description: description,
      surfaced: surfaced
    })
    |> Ecto.Changeset.add_error(:value, "is not valid json: #{inspect(reason)}")
  end
end
