defmodule RestoBookingAppWeb.ReservationController do
  use RestoBookingAppWeb, :controller

  alias RestoBookingApp.Reservations

  action_fallback RestoBookingAppWeb.FallbackController

  # GET /api/reservations[?date=YYYY-MM-DD]
  def index(conn, params) do
    with {:ok, date_opt} <- parse_optional_date(params["date"]) do
      reservations =
        case date_opt do
          nil -> Reservations.list()
          date -> Reservations.list(date: date)
        end

      render(conn, :index, reservations: reservations)
    end
  end

  # GET /api/reservations/:id
  def show(conn, %{"id" => id}) do
    case Reservations.get(id) do
      nil -> {:error, :not_found}
      reservation -> render(conn, :show, reservation: reservation, full: true)
    end
  end

  # POST /api/reservations
  def create(conn, params) do
    with {:ok, reservation} <- Reservations.create(params) do
      conn
      |> put_status(:created)
      |> render(:show, reservation: reservation, full: true, with_token: true)
    end
  end

  # PATCH/PUT /api/reservations/:id?token=...
  def update(conn, %{"id" => id} = params) do
    with {:ok, token} <- fetch_token(params),
         {:ok, reservation} <- Reservations.update(id, token, params) do
      render(conn, :show, reservation: reservation, full: true)
    end
  end

  # DELETE /api/reservations/:id?token=...
  def delete(conn, %{"id" => id} = params) do
    with {:ok, token} <- fetch_token(params),
         :ok <- Reservations.delete(id, token) do
      send_resp(conn, :no_content, "")
    end
  end

  defp fetch_token(%{"token" => token}) when is_binary(token) and token != "", do: {:ok, token}
  defp fetch_token(_), do: {:error, :missing_token}

  defp parse_optional_date(nil), do: {:ok, nil}

  defp parse_optional_date(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> {:ok, date}
      {:error, _} -> {:error, :bad_date}
    end
  end
end
