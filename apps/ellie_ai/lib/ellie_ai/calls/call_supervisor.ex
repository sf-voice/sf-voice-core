defmodule EllieAi.Calls.CallSupervisor do
  @moduledoc """
  dynamic supervisor that owns one CallTree per active call. crashing one
  call's tree never touches another's — `:one_for_one` strategy at this
  layer; the per-call `:rest_for_one` lives inside CallTree itself.
  """

  use DynamicSupervisor

  def start_link(_opts) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
