defmodule EllieAi.Repo.Migrations.CallsAndTurns do
  use Ecto.Migration

  def change do
    create table(:calls, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :org_id, references(:orgs, type: :binary_id, on_delete: :nothing),
        null: false

      # telnyx's per-leg id. unique = idempotency key for webhook retries.
      add :call_control_id, :string, null: false

      add :from_phone, :string
      add :to_phone, :string

      # ringing | active | ended | escalated
      add :status, :string, null: false, default: "ringing"
      add :hangup_reason, :string

      add :started_at, :utc_datetime
      add :ended_at, :utc_datetime

      # rolling EMA of recent turn scores; populated async.
      add :sentiment_score, :float

      timestamps(type: :utc_datetime)
    end

    create unique_index(:calls, [:call_control_id])
    create index(:calls, [:org_id, :inserted_at])

    create table(:transcript_turns, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :call_id, references(:calls, type: :binary_id, on_delete: :delete_all),
        null: false

      # user | assistant
      add :role, :string, null: false
      add :text, :text, null: false

      # 0.0–1.0 from gpt-4o-mini per turn, async.
      add :sentiment_score, :float

      add :started_at, :utc_datetime
      add :ended_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:transcript_turns, [:call_id, :inserted_at])
  end
end
