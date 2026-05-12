defmodule EllieAi.Calls.TranscriptTurn do
  @moduledoc """
  one row per turn of conversation (voice or sms). role/medium enums
  in `Constants`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias EllieAi.Calls.{Call, Constants}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "transcript_turns" do
    field :role, :string
    field :medium, :string, default: "voice"
    field :text, :string
    field :sentiment_score, :float
    field :started_at, :utc_datetime
    field :ended_at, :utc_datetime

    belongs_to :call, Call

    timestamps(type: :utc_datetime)
  end

  @creatable ~w(call_id role medium text sentiment_score started_at ended_at)a
  @required ~w(call_id role text)a

  def changeset(turn, attrs) do
    turn
    |> cast(attrs, @creatable)
    |> validate_required(@required)
    |> validate_inclusion(:role, Constants.roles())
    |> validate_inclusion(:medium, Constants.mediums())
    |> assoc_constraint(:call)
  end
end
