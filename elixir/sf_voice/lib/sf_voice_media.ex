defmodule SfVoiceMedia do
  @moduledoc """
  Elixir SDK for the sf-voice media API.

  build a client with `new/2`, then call the public functions to ingest,
  query, and search media.

  ## quick start

      client = SfVoiceMedia.new("sk-...")

      {:ok, %{task_id: tid}} =
        SfVoiceMedia.ingest(client, %{source: :url, url: "https://example.com/clip.mp4"})

      task = SfVoiceMedia.poll_task(client, tid)

  all functions return `{:ok, result}` or `{:error, %SfVoiceMedia.Error{}}`.
  `poll_task/3` raises `SfVoiceMedia.Error` on timeout.
  """

  alias SfVoiceMedia.{Client, Error}
  alias SfVoiceMedia.Types

  # ── construction ─────────────────────────────────────────────────────────────

  
  
  @doc """
  Builds a SfVoiceMedia.Client preconfigured with the given API key and optional settings.
  
  ## Options
  
    - `:base_url` — API base URL; defaults to "https://api.sf-voice.com". A trailing `/` is removed.
    - `:http_opts` — keyword list forwarded to Req for every request; defaults to `[]`.
  
  ## Examples
  
      client = SfVoiceMedia.new("sk-my-api-key")
  
      client = SfVoiceMedia.new("sk-my-api-key",
        base_url: "https://staging.api.sf-voice.com",
        http_opts: [receive_timeout: 10_000]
      )
  """
  @spec new(String.t(), keyword()) :: Client.t()
  def new(api_key, opts \\ []) do
    base_url =
      opts
      |> Keyword.get(:base_url, "https://api.sf-voice.com")
      |> String.trim_trailing("/")

    %Client{
      api_key: api_key,
      base_url: base_url,
      http_opts: Keyword.get(opts, :http_opts, [])
    }
  end

  # ── public API ───────────────────────────────────────────────────────────────

  
  
  @doc """
  Submit a media file for ingestion from a URL or an S3 key.
  
  Returns immediately with a task identifier that can be inspected with `get_task/2` or awaited with `poll_task/3`.
  
  ## Returns
  
    - `{:ok, response}` — successful response containing at least `task_id` and optionally `asset_id` and other task metadata.
    - `{:error, %SfVoiceMedia.Error{}}` — request failed; contains error details.
  """
  @spec ingest(Client.t(), Types.ingest_request()) ::
            {:ok, Types.ingest_response()} | {:error, Error.t()}
  def ingest(%Client{} = client, request) when is_map(request) do
    post(client, "/v1/ingest", request)
  end

  
  
  @doc """
  Fetches the current state of an ingestion task.
  
  Returns `{:ok, task}` where `task` is a map describing the task (includes a `"status"` field), or `{:error, %SfVoiceMedia.Error{}}` on failure.
  
  ## Examples
  
      {:ok, %{"status" => "ready", "asset_id" => aid}} = SfVoiceMedia.get_task(client, "task_abc123")
  """
  @spec get_task(Client.t(), String.t()) ::
            {:ok, Types.task()} | {:error, Error.t()}
  def get_task(%Client{} = client, task_id) when is_binary(task_id) do
    get(client, "/v1/tasks/#{URI.encode(task_id)}")
  end

  @doc """
  lists assets in the library, paginated.

  ## examples

      {:ok, %{items: items, page_info: info}} =
        SfVoiceMedia.list_assets(client, %{page: 1, limit: 20})

      # no params — uses server defaults
      {:ok, %{items: items}} = SfVoiceMedia.list_assets(client)
  """
  @spec list_assets(Client.t(), Types.list_assets_params()) ::
          {:ok, Types.asset_list_response()} | {:error, Error.t()}
  def list_assets(%Client{} = client, params \\ %{}) when is_map(params) do
    qs = build_query(params)
    get(client, "/v1/assets#{qs}")
  end

  
  
  @doc """
  Retrieve a library asset by its ID.
  
  Returns `{:ok, asset}` when the asset is found, or `{:error, %SfVoiceMedia.Error{}}` on failure.
  """
  @spec get_asset(Client.t(), String.t()) ::
            {:ok, Types.asset()} | {:error, Error.t()}
  def get_asset(%Client{} = client, id) when is_binary(id) do
    get(client, "/v1/assets/#{URI.encode(id)}")
  end

  
  
  @doc """
  Soft-deletes an asset so it is excluded from list results while the backend retains the record.
  
  Returns `:ok` if the deletion was successful (HTTP 204), `{:error, %SfVoiceMedia.Error{}}` otherwise.
  
  ## Examples
  
      :ok = SfVoiceMedia.delete_asset(client, "ast_abc123")
  """
  @spec delete_asset(Client.t(), String.t()) :: :ok | {:error, Error.t()}
  def delete_asset(%Client{} = client, id) when is_binary(id) do
    case request(client, :delete, "/v1/assets/#{URI.encode(id)}") do
      {:ok, _} -> :ok
      {:error, _} = err -> err
    end
  end

  
  
  @doc """
  Run a semantic search over indexed media.
  
  The `request` map must include a `:query` string and may include optional parameters such as `:types` (list of asset types), `:threshold` (similarity threshold), and `:limit` (maximum results). Returns the API response wrapped in `{:ok, result}` or `{:error, %SfVoiceMedia.Error{}}`.
  
  ## Examples
  
      {:ok, %{results: results}} =
        SfVoiceMedia.search(client, %{query: "product roadmap discussion"})
  
      {:ok, %{results: results}} =
        SfVoiceMedia.search(client, %{
          query: "quarterly targets",
          types: [:conversation],
          threshold: 0.7,
          limit: 10
        })
  """
  @spec search(Client.t(), Types.search_request()) ::
          {:ok, Types.search_response()} | {:error, Error.t()}
  def search(%Client{} = client, request) when is_map(request) do
    post(client, "/v1/search", request)
  end

  
  
  @doc """
  Polls an ingestion task until its status becomes "ready" or "failed".
  
  Polls get_task/2 at a fixed interval and returns the final task map when the task reaches "ready".
  Raises `SfVoiceMedia.Error` if the task's status becomes "failed" or if the timeout is exceeded.
  
  Options
  - `:interval_ms` — milliseconds to wait between polls (default: 1500)
  - `:timeout_ms` — maximum total wait in milliseconds (default: 120_000)
  """
  def poll_task(%Client{} = client, task_id, opts \\ []) do
    interval_ms = Keyword.get(opts, :interval_ms, 1_500)
    timeout_ms = Keyword.get(opts, :timeout_ms, 120_000)
    deadline = System.monotonic_time(:millisecond) + timeout_ms

    do_poll(client, task_id, interval_ms, deadline, timeout_ms)
  end

  # ── polling loop (private) ────────────────────────────────────────────────────

  defp do_poll(client, task_id, interval_ms, deadline, timeout_ms) do
    case get_task(client, task_id) do
      {:ok, %{"status" => status} = task} when status in ["ready", "failed"] ->
        if status == "failed" do
          raise Error,
            code: "task_failed",
            message: "task #{task_id} failed: #{task["error"] || "unknown reason"}",
            status: nil
        else
          task
        end

      {:ok, _} ->
        # still in progress — check deadline before sleeping
        now = System.monotonic_time(:millisecond)

        if now + interval_ms > deadline do
          raise Error.poll_timeout(task_id, timeout_ms)
        end

        Process.sleep(interval_ms)
        do_poll(client, task_id, interval_ms, deadline, timeout_ms)

      {:error, %Error{} = err} ->
        raise err
    end
  end

  # ── http helpers ─────────────────────────────────────────────────────────────

  defp get(client, path) do
    case request(client, :get, path) do
      {:ok, body} -> {:ok, body}
      {:error, _} = err -> err
    end
  end

  defp post(client, path, body) do
    case request(client, :post, path, body) do
      {:ok, resp} -> {:ok, resp}
      {:error, _} = err -> err
    end
  end

  # low-level dispatcher — builds Req options and handles errors uniformly
  defp request(%Client{} = client, method, path, body \\ nil) do
    url = client.base_url <> path

    base_opts = [
      url: url,
      headers: [{"x-api-key", client.api_key}],
      decode_json: [keys: :strings]
    ]

    body_opt = if body, do: [json: stringify_keys(body)], else: []

    req_opts = Keyword.merge(base_opts ++ body_opt, client.http_opts)

    result =
      case method do
        :get -> Req.get(req_opts)
        :post -> Req.post(req_opts)
        :delete -> Req.delete(req_opts)
      end

    case result do
      {:ok, %Req.Response{status: status, body: resp_body}} when status in 200..299 ->
        # 204 has no body; normalise to empty map so callers get a consistent type
        {:ok, if(resp_body == "", do: %{}, else: resp_body)}

      {:ok, %Req.Response{status: status, body: resp_body}} ->
        {:error, Error.from_response(status, resp_body)}

      {:error, exception} ->
        # transport-level error (timeout, DNS failure, etc.)
        {:error,
         %Error{
           code: "transport_error",
           message: Exception.message(exception),
           status: nil
         }}
    end
  end

  # converts atom-keyed maps to string-keyed before JSON encoding,
  # so callers can pass %{source: :url} without worrying about encoding
  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), stringify_keys(v)}
      {k, v} -> {k, stringify_keys(v)}
    end)
  end

  defp stringify_keys(v) when is_atom(v), do: Atom.to_string(v)
  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(v), do: v

  # builds a query string from a map, omitting nil values
  defp build_query(params) when map_size(params) == 0, do: ""

  defp build_query(params) do
    qs =
      params
      |> Enum.reject(fn {_, v} -> is_nil(v) end)
      |> Enum.map(fn {k, v} -> "#{k}=#{URI.encode_www_form(to_string(v))}" end)
      |> Enum.join("&")

    if qs == "", do: "", else: "?#{qs}"
  end
end
