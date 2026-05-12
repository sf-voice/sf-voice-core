defmodule RestoBookingApp.Contacts do
  @moduledoc """
  contacts context. multi-tenant: every public function takes
  `org_id` as the first arg. customers and contacts are isolated per
  org, so the same phone number can exist in two orgs as two
  different contact rows owned by two different customers.

  the keystone helper is `find_or_create_for_phone/3`: given an org,
  an E.164 phone, and a name bundle, returns the customer in that
  org who owns the number — creating both customer and contact if
  neither existed.
  """

  import Ecto.Query, except: [update: 2, update: 3]
  import Ecto.Changeset, only: [get_change: 2]

  alias RestoBookingApp.Contacts.{Constants, Contact}
  alias RestoBookingApp.Customers.Customer
  alias RestoBookingApp.Repo

  # ── reads ────────────────────────────────────────────────────────────────

  @doc "fetch one contact by id, scoped to org. nil if missing or cross-org."
  def get(org_id, id) when is_binary(org_id) and is_binary(id) do
    from(c in Contact, where: c.org_id == ^org_id and c.id == ^id) |> Repo.one()
  end

  @doc "find a contact by `(org_id, kind, value)`. returns nil if none."
  def find_by_value(org_id, kind, value)
      when is_binary(org_id) and is_binary(kind) and is_binary(value) do
    Repo.get_by(Contact, org_id: org_id, kind: kind, value: value)
  end

  @doc "list all contacts for a customer (already scoped by FK), preferred-first."
  def list_for_customer(customer_id) when is_binary(customer_id) do
    from(c in Contact,
      where: c.customer_id == ^customer_id,
      order_by: [desc: c.preferred, asc: c.kind, asc: c.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  the customer's preferred contact of a given kind, if any. used to fill in
  a reservation's contact_id default at render time.
  """
  def preferred(%Customer{id: id}, kind) when is_binary(kind) do
    Repo.one(
      from c in Contact,
        where: c.customer_id == ^id and c.kind == ^kind and c.preferred == true,
        limit: 1
    )
  end

  # ── writes ──────────────────────────────────────────────────────────────

  @doc """
  create a contact. attrs must include `org_id`. enforces the
  one-preferred-per-(customer, kind) invariant: if `preferred: true`,
  demote any other preferred contact of the same kind for that
  customer in the same transaction.
  """
  def create(attrs) do
    Repo.transaction(fn ->
      attrs = string_keys(attrs)
      changeset = Contact.changeset(%Contact{}, attrs)

      with true <- changeset.valid? || {:error, changeset},
           :ok <- maybe_demote_others(changeset),
           {:ok, contact} <- Repo.insert(changeset) do
        contact
      else
        {:error, %Ecto.Changeset{} = cs} -> Repo.rollback(cs)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  given an org, an E.164 phone, and a name bundle, returns the
  customer in that org who owns the phone — creating both customer
  and contacts if neither existed.

  `customer_attrs` may include `:id` — used by ellie so the resto-side
  customer uuid matches the one ellie already minted in its local stub.
  if the phone already maps to a different customer, the existing
  customer wins (caller reconciles ids on its end).

  always runs in a transaction so a partial create can't leak.
  """
  def find_or_create_for_phone(org_id, phone, customer_attrs \\ %{})
      when is_binary(org_id) and is_binary(phone) do
    customer_attrs = string_keys(customer_attrs)
    email = Map.get(customer_attrs, :email)
    customer_attrs = Map.delete(customer_attrs, :email)

    Repo.transaction(fn ->
      case find_by_value(org_id, Constants.phone(), phone) do
        %Contact{customer_id: cust_id} ->
          customer = Repo.get!(Customer, cust_id)
          maybe_add_email(org_id, customer, email)

          {:ok, refreshed} =
            customer
            |> Customer.changeset(merge_name_updates(customer_attrs))
            |> Repo.update()

          refreshed

        nil ->
          {:ok, customer} = create_customer(org_id, customer_attrs)

          {:ok, _phone_contact} =
            insert_contact_unsafe(org_id, customer, Constants.phone(), phone, preferred: true)

          maybe_add_email(org_id, customer, email)
          customer
      end
    end)
  end

  # on the "phone already exists" path, fill in any missing name fields
  # from the caller (resto trusts ellie's latest read) and always bump
  # last_seen_at.
  defp merge_name_updates(attrs) do
    attrs
    |> Map.take([:salutation, :first_name, :last_name, :notes])
    |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)
    |> Map.new()
    |> Map.put(:last_seen_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end

  # ── helpers ──────────────────────────────────────────────────────────────

  defp maybe_demote_others(%Ecto.Changeset{} = cs) do
    case {get_change(cs, :preferred), get_change(cs, :customer_id), get_change(cs, :kind)} do
      {true, customer_id, kind} when is_binary(customer_id) and is_binary(kind) ->
        from(c in Contact,
          where: c.customer_id == ^customer_id and c.kind == ^kind and c.preferred == true
        )
        |> Repo.update_all(set: [preferred: false])

        :ok

      _ ->
        :ok
    end
  end

  defp insert_contact_unsafe(org_id, %Customer{id: id}, kind, value, opts) do
    %Contact{}
    |> Contact.changeset(%{
      org_id: org_id,
      customer_id: id,
      kind: kind,
      value: value,
      preferred: Keyword.get(opts, :preferred, false)
    })
    |> Repo.insert()
  end

  defp maybe_add_email(_org_id, _customer, nil), do: :ok
  defp maybe_add_email(_org_id, _customer, ""), do: :ok

  defp maybe_add_email(org_id, %Customer{} = customer, email) when is_binary(email) do
    case find_by_value(org_id, Constants.email(), email) do
      nil ->
        case insert_contact_unsafe(org_id, customer, Constants.email(), email, preferred: true) do
          {:ok, _} -> :ok
          {:error, _} -> :ok
        end

      _existing ->
        :ok
    end
  end

  defp create_customer(org_id, attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs =
      attrs
      |> Map.put(:org_id, org_id)
      |> Map.put_new(:first_seen_at, now)
      |> Map.put_new(:last_seen_at, now)

    %Customer{}
    |> Customer.changeset(attrs)
    |> Repo.insert()
  end

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
