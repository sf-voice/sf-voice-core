defmodule EllieAi.Calls.Call do
  @moduledoc """
  one row per inbound phone call. status/role enums in `Constants`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias EllieAi.Calls.{Constants, TranscriptTurn}
  alias EllieAi.Customers.CustomerSummary
  alias EllieAi.Orgs.Org

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "calls" do
    # grouping key tel_<caller>_<callee> — ties voice + sms for the same number pair.
    field :channel_id, :string
    # provider is "telnyx" today; column future-proofs a switch.
    field :provider, :string, default: "telnyx"
    # telnyx's call_control_id; used as the Registry key.
    field :provider_id, :string
    field :from_phone, :string
    field :to_phone, :string
    field :status, :string, default: "ringing"
    field :hangup_reason, :string
    field :started_at, :utc_datetime
    field :ended_at, :utc_datetime
    field :sentiment_score, :float
    # nil until Archivist finalises the wav upload; UI gates the player on this.
    field :audio_s3_key, :string
    field :audio_duration_ms, :integer
    # nil while in-flight or if summarization failed.
    field :summary, :string

    belongs_to :org, Org
    belongs_to :customer, CustomerSummary
    has_many :transcript_turns, TranscriptTurn

    timestamps(type: :utc_datetime)
  end

  @creatable ~w(org_id customer_id channel_id provider provider_id from_phone to_phone status hangup_reason
                started_at ended_at sentiment_score audio_s3_key audio_duration_ms summary)a
  @required ~w(org_id channel_id provider provider_id status)a

  def changeset(call, attrs) do
    call
    |> cast(attrs, @creatable)
    |> validate_required(@required)
    |> validate_inclusion(:status, Constants.statuses())
    |> unique_constraint(:provider_id)
    |> assoc_constraint(:org)
  end
end
