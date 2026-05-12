defmodule EllieAi.Repo.Migrations.CreateCustomerSummary do
  use Ecto.Migration


  def change do
    create table(:customer_summary, primary_key: false) do
      add :id, :binary_id, primary_key: true
      # nightly synced back from whichever pos/booking integration we have.
      add :org_customer_id, :string
      add :salutation, :string
      add :first_name, :string
      add :last_name, :string
      add :notes, :string

      add :phone_e164, :string
      add :email, :string

      add :first_seen_at, :utc_datetime
      add :last_seen_at, :utc_datetime
      # set on every resto sync touch; reconcile cron uses it to know
      # when this row last shook hands with resto. NOT NULL enforced at
      # the schema level (validate_required).
      add :last_synced_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:customer_summary, [:phone_e164])
    create index(:customer_summary, [:last_seen_at])
  end
end
