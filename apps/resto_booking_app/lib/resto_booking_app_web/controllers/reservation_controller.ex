defmodule RestoBookingAppWeb.ReservationController do
  use RestoBookingAppWeb, :controller

  alias RestoBookingApp.Reservations

  action_fallback RestoBookingAppWeb.FallbackController

  def index(conn, params) do
    with {:ok, date_opt} <- parse_optional_date(params["date"]) do
      opts =
        []
        |> maybe_put(:date, date_opt)
        |> maybe_put(:customer_id, params["customer_id"])
        |> Keyword.put(:preload, [:customer, :contact])

      reservations = Reservations.list(conn.assigns.org_id, opts)
      render(conn, :index, reservations: reservations)
    end
  end

  def show(conn, %{"id" => id}) do
    case Reservations.get(conn.assigns.org_id, id, preload: [:customer, :contact]) do
      nil -> {:error, :not_found}
      reservation -> render(conn, :show, reservation: reservation)
    end
  end

  def create(conn, params) do
    attrs = params |> Map.drop(["org_slug"]) |> Map.put("org_id", conn.assigns.org_id)

    with {:ok, reservation} <- Reservations.create(attrs) do
      reservation = RestoBookingApp.Repo.preload(reservation, [:customer, :contact])

      conn
      |> put_status(:created)
      |> render(:show, reservation: reservation, with_token: true)
    end
  end

  def update(conn, %{"id" => id} = params) do
    attrs = Map.drop(params, ["id", "org_slug", "token"])

    with {:ok, reservation} <- Reservations.update(conn.assigns.org_id, id, attrs) do
      reservation = RestoBookingApp.Repo.preload(reservation, [:customer, :contact])
      render(conn, :show, reservation: reservation)
    end
  end

  def delete(conn, %{"id" => id}) do
    with :ok <- Reservations.delete(conn.assigns.org_id, id) do
      send_resp(conn, :no_content, "")
    end
  end

  defp parse_optional_date(nil), do: {:ok, nil}

  defp parse_optional_date(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> {:ok, date}
      {:error, _} -> {:error, :bad_date}
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, _key, ""), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
