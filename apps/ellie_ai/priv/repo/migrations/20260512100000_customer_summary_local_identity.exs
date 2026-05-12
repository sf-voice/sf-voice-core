defmodule EllieAi.Repo.Migrations.CustomerSummaryLocalIdentity do
  use Ecto.Migration

  def up do
    alter table(:customer_summary) do
      # nullable: ellie may mint a local stub before resto knows the caller.
      add :resto_customer_id, :string
      # resto's contact row id that matched our phone lookup.
      add :contact_id, :string
    end

    # backfill: existing rows were all upserted from resto, so their local
    # id IS resto's customer id — copy it so reconcile still finds them.
    execute("UPDATE customer_summary SET resto_customer_id = id WHERE resto_customer_id IS NULL")

    create index(:customer_summary, [:resto_customer_id])
    create index(:customer_summary, [:contact_id])
  end

  def down do
    drop_if_exists index(:customer_summary, [:contact_id])
    drop_if_exists index(:customer_summary, [:resto_customer_id])

    alter table(:customer_summary) do
      remove :contact_id
      remove :resto_customer_id
    end
  end
end
