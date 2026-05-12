defmodule EllieAi.Repo.Migrations.AddCustomerAndSummaryToCalls do
  use Ecto.Migration

  def up do
    alter table(:calls) do
      # durable link to customer_summary, replacing the phone-string match
      # we did everywhere. nilify on customer delete so call history survives.
      add :customer_id, references(:customer_summary, type: :binary_id, on_delete: :nilify_all)
      # 1-2 sentence post-call summary from gpt-4o-mini. nil while the call
      # is in flight or summarization failed.
      add :summary, :text
    end

    # backfill: link every existing call to its customer by phone match.
    # nullable so a future caller without a cached customer row is fine.
    execute """
    UPDATE calls
    SET customer_id = (
      SELECT cs.id FROM customer_summary cs
      WHERE cs.org_id = calls.org_id
        AND cs.phone_e164 = calls.from_phone
      LIMIT 1
    )
    WHERE customer_id IS NULL AND from_phone IS NOT NULL
    """

    create index(:calls, [:customer_id])
  end

  def down do
    drop index(:calls, [:customer_id])

    alter table(:calls) do
      remove :customer_id
      remove :summary
    end
  end
end
