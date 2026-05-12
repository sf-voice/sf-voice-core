defmodule EllieAi.Tools.Catalog do


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

  @doc "find a tool module by its `name/0` string, or nil."
  def find(name) when is_binary(name) do
    Enum.find(all(), fn module -> module.name() == name end)
  end

  @doc "is this tool name a write tool (model-callable, mutates resto)?"
  def write?(name) when is_binary(name) do
    Enum.any?(@write, fn module -> module.name() == name end)
  end
end
