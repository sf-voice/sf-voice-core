defmodule EllieAi.Repo.Migrations.CreateToolCalls do
  use Ecto.Migration

  def change do
    create table(:tool_calls, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :call_id, references(:calls, type: :binary_id, on_delete: :delete_all),
        null: false

      # openai's function_call id; nil for `before`/`after` rows (no model frame).
      add :openai_call_id, :string

      # before | midflight | after — where in the call lifecycle the tool fired.
      add :type, :string, null: false, default: "midflight"

      add :tool_name, :string, null: false

      add :arguments, :map, null: false, default: %{}
      add :result, :map

      # pending | ok | error
      add :status, :string, null: false, default: "pending"
      add :error, :text
      add :duration_ms, :integer

      add :replayed_from_id,
          references(:tool_calls, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:tool_calls, [:call_id, :inserted_at])
    # AudioBridge looks up the pending midflight row by this when the
    # model's function_call_arguments.done arrives.
    create index(:tool_calls, [:openai_call_id])
  end
end
