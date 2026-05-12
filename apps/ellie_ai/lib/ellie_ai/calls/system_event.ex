defmodule EllieAi.Calls.SystemEvent do
  @moduledoc """
  one lifecycle event in a call (not a transcript turn, not a tool call).
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias EllieAi.Calls.Call

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "system_events" do
    field :source, :string
    field :kind, :string
    field :message, :string
    field :payload, :map

    belongs_to :call, Call

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @creatable ~w(call_id source kind message payload)a
  @required ~w(call_id source kind)a

  def changeset(event, attrs) do
    event
    |> cast(attrs, @creatable)
    |> validate_required(@required)
    |> assoc_constraint(:call)
  end
end
