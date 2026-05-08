defmodule RestoBookingAppWeb.TableJSON do
  @moduledoc "renders the static floor-plan layout"

  def index(%{tables: tables, seat_total: seat_total}) do
    %{seat_total: seat_total, tables: Enum.map(tables, &row/1)}
  end

  defp row(%{id: id, seats: seats, shape: shape, x: x, y: y}) do
    %{id: id, seats: seats, shape: shape, x: x, y: y}
  end
end
