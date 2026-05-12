defmodule RestoBookingApp.Repo.Migrations.CreateContacts do
  use Ecto.Migration

  def up do
    create table(:contacts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :customer_id,
          references(:customers, type: :binary_id, on_delete: :delete_all),
          null: false

      add :kind, :string, null: false
      add :value, :string, null: false
      add :label, :string
      add :preferred, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create index(:contacts, [:customer_id])
    create unique_index(:contacts, [:kind, :value])
  end

  def down do
    drop_if_exists unique_index(:contacts, [:kind, :value])
    drop_if_exists index(:contacts, [:customer_id])
    drop table(:contacts)
  end
end
