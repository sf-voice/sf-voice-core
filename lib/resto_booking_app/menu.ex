defmodule RestoBookingApp.Menu do
  @moduledoc """
  static menu, three services a day. prices in cents to avoid float math.
  dietary tags follow common conventions: :vegan, :vegetarian, :gluten_free,
  :nut_free, :dairy_free.
  """

  @menu %{
    breakfast: [
      %{name: "Sourdough Toast & Jam", price_cents: 700, dietary: [:vegan]},
      %{name: "Garden Veg Shakshuka", price_cents: 1400, dietary: [:vegetarian, :gluten_free]},
      %{name: "Smoked Salmon Bagel", price_cents: 1600, dietary: [:nut_free]},
      %{name: "Buckwheat Pancakes", price_cents: 1200, dietary: [:vegetarian, :nut_free]},
      %{name: "Oat Porridge, Berries", price_cents: 900, dietary: [:vegan, :gluten_free]}
    ],
    lunch: [
      %{name: "House Caesar Salad", price_cents: 1500, dietary: [:vegetarian]},
      %{name: "Roasted Squash Risotto", price_cents: 1800, dietary: [:vegetarian, :gluten_free]},
      %{name: "Steak Frites", price_cents: 2600, dietary: [:gluten_free]},
      %{name: "Crispy Tofu Bowl", price_cents: 1700, dietary: [:vegan, :gluten_free, :nut_free]},
      %{name: "Mushroom Tagliatelle", price_cents: 1900, dietary: [:vegetarian]}
    ],
    dinner: [
      %{name: "Charred Octopus", price_cents: 2400, dietary: [:gluten_free, :dairy_free]},
      %{name: "Wagyu Tartare", price_cents: 2900, dietary: [:gluten_free, :nut_free]},
      %{name: "Truffle Tagliolini", price_cents: 3200, dietary: [:vegetarian]},
      %{name: "Branzino al Sale", price_cents: 3600, dietary: [:gluten_free, :dairy_free]},
      %{name: "Beetroot Wellington", price_cents: 2800, dietary: [:vegan]},
      %{name: "Dark Chocolate Tart", price_cents: 1100, dietary: [:vegetarian, :gluten_free]}
    ]
  }

  @services Map.keys(@menu)

  @doc "the entire menu, keyed by service"
  def all, do: @menu

  @doc "items for a specific service (:breakfast | :lunch | :dinner)"
  def for_service(service) when service in @services, do: Map.fetch!(@menu, service)
  def for_service(_), do: []

  @doc "list of services we offer"
  def services, do: @services
end
