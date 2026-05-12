defmodule EllieAi.Tools.Catalog do
  @moduledoc "registry of tool modules exposed to the realtime session."

  alias EllieAi.Tools

  @read [
    Tools.LookupAvailability
  ]

  @write [
    Tools.UpsertCustomer,
    Tools.CreateReservation,
    Tools.ModifyReservation,
    Tools.CancelReservation,
    Tools.RequestHumanHandoff
  ]

  def all, do: @read ++ @write

  def find(name) when is_binary(name) do
    Enum.find(all(), fn module -> module.name() == name end)
  end

  def write?(name) when is_binary(name) do
    Enum.any?(@write, fn module -> module.name() == name end)
  end
end
