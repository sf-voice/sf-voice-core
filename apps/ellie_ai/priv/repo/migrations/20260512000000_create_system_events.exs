defmodule EllieAi.Repo.Migrations.CreateSystemEvents do
  use Ecto.Migration

  def change do
    create table(:system_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :call_id, references(:calls, type: :binary_id, on_delete: :delete_all), null: false
      # source: telnyx | openai | vad | media | escalator | sentiment
      add :source, :string, null: false
      # free-form, namespaced by source — e.g. "openai.session.updated".
      add :kind, :string, null: false
      add :message, :string
      # raw event map for replay during triage.
      add :payload, :map

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:system_events, [:call_id, :inserted_at])
  end
end
