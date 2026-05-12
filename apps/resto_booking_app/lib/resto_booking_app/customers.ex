defmodule RestoBookingApp.Customers do
  @moduledoc """
  customers context. multi-tenant: every public function takes
  `org_id` as the first arg so cross-org reads/writes are impossible.
  identity-only — contact info lives in `RestoBookingApp.Contacts`.

  ellie polls resto's http api when it needs the current state; resto
  never reaches out to ellie.
  """

  import Ecto.Query, except: [update: 2, update: 3]

  alias RestoBookingApp.Customers.Customer
  alias RestoBookingApp.Repo

  @doc "list customers within an org, newest activity first."
  def list(org_id, opts \\ []) when is_binary(org_id) do
    limit = Keyword.get(opts, :limit, 500)
    preload = Keyword.get(opts, :preload, [])

    Customer
    |> where([c], c.org_id == ^org_id)
    |> order_by([c], desc: c.last_seen_at)
    |> limit(^limit)
    |> Repo.all()
    |> maybe_preload(preload)
  end

  @doc "fetch one customer by id, scoped to org. accepts `:preload`."
  def get(org_id, id, opts \\ []) when is_binary(org_id) do
    Customer
    |> where([c], c.org_id == ^org_id and c.id == ^id)
    |> Repo.one()
    |> maybe_preload(Keyword.get(opts, :preload, []))
  end

  @doc "update a customer (identity fields only). org_id scopes the lookup."
  def update(org_id, %Customer{org_id: scope} = customer, attrs) when is_binary(org_id) do
    if scope == org_id do
      customer
      |> Customer.changeset(string_keys(attrs))
      |> Repo.update()
    else
      {:error, :not_found}
    end
  end

  def update(org_id, id, attrs) when is_binary(org_id) and is_binary(id) do
    case get(org_id, id) do
      nil -> {:error, :not_found}
      %Customer{} = c -> update(org_id, c, attrs)
    end
  end

  @doc "bump last_seen_at to now on a customer in this org."
  def touch_last_seen(org_id, %Customer{} = customer) do
    update(org_id, customer, %{
      last_seen_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end

  # ── helpers ──────────────────────────────────────────────────────────────

  defp maybe_preload(nil, _), do: nil
  defp maybe_preload(record, []), do: record
  defp maybe_preload(record, preload), do: Repo.preload(record, preload)

  defp string_keys(attrs) when is_map(attrs) do
    Map.new(attrs, fn
      {k, v} when is_atom(k) -> {k, v}
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
    end)
  rescue
    ArgumentError -> attrs
  end

  defp string_keys(other), do: other
end
