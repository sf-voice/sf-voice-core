defmodule EllieAi.Repo.Migrations.PromptsUniqueOrgVersion do
  use Ecto.Migration

  # save_new_version/2 computes the next version as max(version) + 1 then
  # inserts. without a unique constraint, two concurrent calls in the same
  # org could both compute N and both insert version=N. SQLite serialises
  # writers but the read-then-write window is still wide enough to race
  # under WAL. this index makes the duplicate insert fail loudly so the
  # transaction rolls back and the caller can retry / report.
  def change do
    create unique_index(:prompts, [:org_id, :version])
  end
end
