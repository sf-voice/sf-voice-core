defmodule RestoBookingAppWeb.CustomerController do
  @moduledoc """
  http surface for an org's customer records. ellie polls these
  endpoints during calls (lookup_customer waterfall: local → resto →
  ask) and on its nightly reconciliation cron. resto never reaches
  outward; this controller is the only contact surface.

  every action runs inside the `/api/orgs/:org_slug` scope, so
  `conn.assigns.org_id` is always present.

  POST is idempotent on `(org_id, phone)` via
  `Contacts.find_or_create_for_phone/3`.
  """

  use RestoBookingAppWeb, :controller

  alias RestoBookingApp.{Contacts, Customers}
  alias RestoBookingApp.Contacts.Constants, as: ContactConstants

  action_fallback RestoBookingAppWeb.FallbackController

  def index(conn, params) do
    limit =
      case Integer.parse(params["limit"] || "") do
        {n, ""} when n > 0 and n <= 1000 -> n
        _ -> 500
      end

    customers = Customers.list(conn.assigns.org_id, limit: limit, preload: :contacts)
    render(conn, :index, customers: customers)
  end

  def show(conn, %{"id" => id}) do
    case Customers.get(conn.assigns.org_id, id, preload: :contacts) do
      nil -> {:error, :not_found}
      customer -> render(conn, :show, customer: customer)
    end
  end

  def show_by_phone(conn, %{"phone" => phone}) do
    org_id = conn.assigns.org_id

    case Contacts.find_by_value(org_id, ContactConstants.phone(), phone) do
      nil ->
        {:error, :not_found}

      contact ->
        customer = Customers.get(org_id, contact.customer_id, preload: :contacts)
        render(conn, :show, customer: customer)
    end
  end

  def create(conn, %{"phone" => phone} = params)
      when is_binary(phone) and phone != "" do
    org_id = conn.assigns.org_id
    customer_attrs = Map.drop(params, ["phone", "org_slug"])

    with {:ok, customer} <- Contacts.find_or_create_for_phone(org_id, phone, customer_attrs) do
      customer = RestoBookingApp.Repo.preload(customer, :contacts)

      conn
      |> put_status(:created)
      |> render(:show, customer: customer)
    end
  end

  def create(_conn, _params), do: {:error, :missing_phone}

  def update(conn, %{"id" => id} = params) do
    org_id = conn.assigns.org_id
    attrs = Map.drop(params, ["id", "org_slug"])

    with {:ok, customer} <- Customers.update(org_id, id, attrs) do
      customer = RestoBookingApp.Repo.preload(customer, :contacts)
      render(conn, :show, customer: customer)
    end
  end
end
