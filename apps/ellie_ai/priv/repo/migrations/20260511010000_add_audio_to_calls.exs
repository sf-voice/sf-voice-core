defmodule EllieAi.Repo.Migrations.AddAudioToCalls do
  use Ecto.Migration

  def change do
    alter table(:calls) do
      add :audio_s3_key, :string
      add :audio_duration_ms, :integer
    end
  end
end
