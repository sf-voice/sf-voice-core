defmodule RestoBookingApp.Menu.Constants do
  @moduledoc """
  shared menu constants. dietary tags are single-use inside `MenuItem`
  so they stay there as a module attribute.
  """

  # services we offer (string form, matching the column shape)
  def services, do: ~w(breakfast lunch dinner)
end
