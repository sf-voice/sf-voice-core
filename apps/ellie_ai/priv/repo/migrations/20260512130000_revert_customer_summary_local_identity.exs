defmodule EllieAi.Repo.Migrations.RevertCustomerSummaryLocalIdentity do
  use Ecto.Migration

  def up do
    # contract change: customer_summary.id is once again the same uuid as
    # resto's customers.id. local stubs from the split era have ellie-minted
    # ids that don't exist in resto, so wipe rather than try to reconcile.
    execute("DELETE FROM customer_summary")

    drop_if_exists index(:customer_summary, [:contact_id])
    drop_if_exists index(:customer_summary, [:resto_customer_id])

    alter table(:customer_summary) do
      remove :contact_id
      remove :resto_customer_id
    end
  end

  def down do
    alter table(:customer_summary) do
      add :resto_customer_id, :string
      add :contact_id, :string
    end

    create index(:customer_summary, [:resto_customer_id])
    create index(:customer_summary, [:contact_id])
  end
end
