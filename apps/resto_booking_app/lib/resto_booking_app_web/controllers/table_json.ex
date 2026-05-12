defmodule RestoBookingAppWeb.TableJSON do
  @moduledoc "renders an org's floor-plan layout"

  alias RestoBookingApp.Tables.Table

  def index(%{tables: tables, seat_total: seat_total}) do
    %{seat_total: seat_total, tables: Enum.map(tables, &row/1)}
  end

  defp row(%Table{} = t) do
    %{id: t.slug, seats: t.seats, shape: t.shape, x: t.x, y: t.y}
  end
end
