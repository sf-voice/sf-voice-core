defmodule RestoBookingAppWeb.FallbackController do
  @moduledoc """
  uniform json error responses for the api controllers. each tagged tuple
  the contexts return maps to a status + tiny json body so api consumers
  always know what shape to expect.
  """

  use Phoenix.Controller, formats: [:json]

  alias RestoBookingAppWeb.ChangesetJSON

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: ChangesetJSON)
    |> render(:error, changeset: changeset)
  end

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> json(%{errors: %{detail: "Not Found"}})
  end

  def call(conn, {:error, :invalid_token}) do
    conn
    |> put_status(:forbidden)
    |> json(%{errors: %{detail: "Invalid cancel token"}})
  end

  def call(conn, {:error, :missing_token}) do
    conn
    |> put_status(:bad_request)
    |> json(%{errors: %{detail: "Missing token query parameter"}})
  end

  def call(conn, {:error, :bad_date}) do
    conn
    |> put_status(:bad_request)
    |> json(%{errors: %{detail: "Invalid date — expected YYYY-MM-DD"}})
  end
end
