defmodule RestoBookingAppWeb.MenuJSON do
  @moduledoc "shapes per-org menu rows into json-friendly maps."

  alias RestoBookingApp.MenuItems.MenuItem

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

  defp item(%MenuItem{} = mi) do
    %{
      name: mi.name,
      price_cents: mi.price_cents,
      dietary: MenuItem.dietary_list(mi)
    }
  end
end
