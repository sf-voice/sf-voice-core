defmodule EllieAi.Resto do
  @moduledoc """
  """

  require Logger

  alias EllieAi.Orgs.Org
  alias EllieAi.Utils

  def get_customer_by_phone(%Org{} = org, phone) when is_binary(phone) do
    with {:ok, e164} <- normalize_phone(phone),
         url = endpoint(org, "/customers/by_phone/#{URI.encode(e164)}"),
         {:ok, resp} <- request(:get, url) do
      handle_get_response(resp, "customer")
    end
  end

  # resto's POST is keyed on `(org, phone)`, so retries are safe.
  def create_customer(%Org{} = org, attrs) when is_map(attrs) do
    phone = Map.get(attrs, :phone) || Map.get(attrs, "phone")

    with {:ok, e164} <- normalize_phone(phone),
         body = attrs |> Utils.stringify_keys() |> Map.put("phone", e164),
         url = endpoint(org, "/customers"),
         {:ok, resp} <- request(:post, url, json: body) do
      handle_get_response(resp, "customer")
    end
  end

  def get_availability(%Org{} = org, date) when is_binary(date) do
    url = endpoint(org, "/availability?date=#{URI.encode(date)}")

    case request(:get, url) do
      {:ok, %{status: 200, body: %{"tables" => _} = body}} -> {:ok, body}
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:ok, %{status: code, body: body}} when code in 400..499 -> {:error, {:permanent, body}}
      {:ok, %{status: _}} -> {:error, {:transient, "5xx"}}
      {:error, reason} -> {:error, {:transient, reason}}
    end
  end

  def create_reservation(%Org{} = org, attrs) when is_map(attrs) do
    url = endpoint(org, "/reservations")
    body = Utils.stringify_keys(attrs)

    case request(:post, url, json: body) do
      {:ok, %{status: 201, body: %{"reservation" => res}}} -> {:ok, res}
      {:ok, %{status: 200, body: %{"reservation" => res}}} -> {:ok, res}
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:ok, %{status: code, body: body}} when code in 400..499 -> {:error, {:permanent, body}}
      {:ok, %{status: _}} -> {:error, {:transient, "5xx"}}
      {:error, reason} -> {:error, {:transient, reason}}
    end
  end

  def update_reservation(%Org{} = org, id, attrs)
      when is_binary(id) and is_map(attrs) do
    url = endpoint(org, "/reservations/#{id}")
    body = Utils.stringify_keys(attrs)

    case request(:put, url, json: body) do
      {:ok, %{status: 200, body: %{"reservation" => res}}} -> {:ok, res}
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:ok, %{status: code, body: body}} when code in 400..499 -> {:error, {:permanent, body}}
      {:ok, %{status: _}} -> {:error, {:transient, "5xx"}}
      {:error, reason} -> {:error, {:transient, reason}}
    end
  end

  def cancel_reservation(%Org{} = org, id) when is_binary(id) do
    url = endpoint(org, "/reservations/#{id}")

    case request(:delete, url) do
      {:ok, %{status: 204}} -> {:ok, %{cancelled: true, id: id}}
      {:ok, %{status: 200}} -> {:ok, %{cancelled: true, id: id}}
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:ok, %{status: code, body: body}} when code in 400..499 -> {:error, {:permanent, body}}
      {:ok, %{status: _}} -> {:error, {:transient, "5xx"}}
      {:error, reason} -> {:error, {:transient, reason}}
    end
  end

  # used by the model to find a reservation to modify or cancel when
  # the caller doesn't know the reservation id.
  def list_customer_reservations(%Org{} = org, customer_id) when is_binary(customer_id) do
    url = endpoint(org, "/customers/#{customer_id}/reservations")

    case request(:get, url) do
      {:ok, %{status: 200, body: %{"reservations" => list}}} when is_list(list) -> {:ok, list}
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:ok, %{status: code, body: body}} when code in 400..499 -> {:error, {:permanent, body}}
      {:ok, %{status: _}} -> {:error, {:transient, "5xx"}}
      {:error, reason} -> {:error, {:transient, reason}}
    end
  end

  def list_customers(%Org{} = org, opts \\ []) do
    limit = Keyword.get(opts, :limit, 1000)
    url = endpoint(org, "/customers?limit=#{limit}")

    case request(:get, url) do
      {:ok, %{status: 200, body: %{"customers" => list}}} when is_list(list) -> {:ok, list}
      {:ok, %{status: code, body: body}} when code in 400..499 -> {:error, {:permanent, body}}
      {:ok, %{status: _}} -> {:error, {:transient, "5xx"}}
      {:error, reason} -> {:error, {:transient, reason}}
    end
  end

  def list_menu_items(%Org{} = org) do
    url = endpoint(org, "/menu")

    case request(:get, url) do
      {:ok, %{status: 200, body: %{"services" => services}}} when is_list(services) ->
        # resto returns nested services [{service, items}]; flatten + tag
        # each item with its service so ellie can upsert directly.
        items =
          Enum.flat_map(services, fn %{"service" => service, "items" => items} ->
            Enum.with_index(items)
            |> Enum.map(fn {item, idx} ->
              item |> Map.put("service", service) |> Map.put_new("sort_order", idx)
            end)
          end)

        {:ok, items}

      {:ok, %{status: code, body: body}} when code in 400..499 ->
        {:error, {:permanent, body}}

      {:ok, %{status: _}} ->
        {:error, {:transient, "5xx"}}

      {:error, reason} ->
        {:error, {:transient, reason}}
    end
  end

  defp handle_get_response(%{status: 200, body: %{} = body}, key) do
    case Map.fetch(body, key) do
      {:ok, payload} -> {:ok, payload}
      :error -> {:error, {:permanent, "missing key #{inspect(key)} in response"}}
    end
  end

  defp handle_get_response(%{status: 201, body: %{} = body}, key),
    do: handle_get_response(%{status: 200, body: body}, key)

  defp handle_get_response(%{status: 404}, _key), do: {:error, :not_found}

  defp handle_get_response(%{status: code, body: body}, _key) when code in 400..499 do
    {:error, {:permanent, body}}
  end

  defp handle_get_response(%{status: _}, _key), do: {:error, {:transient, "5xx"}}

  defp request(method, url, opts \\ []) do
    base_opts = [
      url: url,
      method: method,
      auth: {:bearer, token!()},
      receive_timeout: receive_timeout(),
      retry: :transient,
      max_retries: 2
    ]

    started = System.monotonic_time(:millisecond)

    case Req.request(base_opts ++ opts) do
      {:ok, response} ->
        log_request(method, url, response.status, started)
        {:ok, decode_body(response)}

      {:error, reason} ->
        log_request(method, url, "transport_error", started)
        {:error, {:transient, reason}}
    end
  end

  defp log_request(method, url, status, started_ms) do
    dur = System.monotonic_time(:millisecond) - started_ms

    Logger.info(
      "resto #{method |> Atom.to_string() |> String.upcase()} #{strip_base(url)} " <>
        "→ #{status} in #{dur}ms"
    )
  end

  # base url is the same every call — log only the /api/orgs/... path.
  defp strip_base(url) do
    case String.split(url, "/api/", parts: 2) do
      [_, rest] -> "/api/" <> rest
      _ -> url
    end
  end

  defp decode_body(%{body: body} = response) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> %{response | body: decoded}
      {:error, _} -> response
    end
  end

  defp decode_body(response), do: response

  # `path` always starts with a leading slash so the join is unambiguous.
  defp endpoint(%Org{resto_base_url: base, resto_org_slug: slug}, path)
       when is_binary(base) and is_binary(slug) and is_binary(path) do
    "#{String.trim_trailing(base, "/")}/api/orgs/#{slug}#{path}"
  end

  defp token! do
    case Application.get_env(:ellie_ai, :internal_api_token) do
      v when is_binary(v) and v != "" -> v
      _ -> raise "INTERNAL_API_TOKEN missing — runtime config didn't load it"
    end
  end

  defp receive_timeout do
    Application.get_env(:ellie_ai, __MODULE__, [])[:receive_timeout] || 5_000
  end

  defp normalize_phone(phone) when is_binary(phone) and phone != "" do
    case EllieAi.Phones.to_e164(phone) do
      {:ok, e164} -> {:ok, e164}
      {:error, reason} -> {:error, {:permanent, reason}}
    end
  end

  defp normalize_phone(_), do: {:error, {:permanent, "phone is required"}}

end
