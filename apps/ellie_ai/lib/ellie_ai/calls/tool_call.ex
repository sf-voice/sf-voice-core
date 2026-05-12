defmodule EllieAi.Calls.ToolCall do
  @moduledoc """
  one row per tool invocation inside a call. type/status enums in
  `Constants`. replays insert a new row pointing at the original via
  `replayed_from_id`; the original is never mutated.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias EllieAi.Calls.{Call, Constants}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "tool_calls" do
    field :openai_call_id, :string
    field :type, :string, default: "midflight"
    field :tool_name, :string
    field :arguments, :map, default: %{}
    field :result, :map
    field :status, :string, default: "pending"
    field :error, :string
    field :duration_ms, :integer

    belongs_to :call, Call
    # self-referential: replayed_from_id points at the original row when
    # this is a replay; nil on originals.
    belongs_to :replayed_from, __MODULE__

    timestamps(type: :utc_datetime)
  end

  @creatable ~w(call_id openai_call_id type tool_name arguments
                result status error duration_ms replayed_from_id)a
  @required ~w(call_id type tool_name status)a

  def changeset(tool_call, attrs) do
    tool_call
    |> cast(attrs, @creatable)
    |> validate_required(@required)
    |> validate_inclusion(:type, Constants.tool_call_types())
    |> validate_inclusion(:status, Constants.tool_call_statuses())
    |> assoc_constraint(:call)
  end
end
