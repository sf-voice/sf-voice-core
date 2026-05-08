defmodule RestoBookingAppWeb.MenuJSON do
  @moduledoc "shapes the menu module into json-friendly maps"

  def index(%{menu: menu}) do
    %{
      services:
        Enum.map(menu, fn {service, items} ->
          %{
            service: service,
            items: Enum.map(items, &item/1)
          }
        end)
    }
  end

  defp item(%{name: name, price_cents: price, dietary: dietary}) do
    %{name: name, price_cents: price, dietary: dietary}
  end
end
