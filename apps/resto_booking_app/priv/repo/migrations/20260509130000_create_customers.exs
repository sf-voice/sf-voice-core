defmodule RestoBookingApp.Repo.Migrations.CreateCustomers do
  use Ecto.Migration


  def up do
    create table(:customers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :salutation, :string
      add :first_name, :string
      add :last_name, :string
      add :notes, :string
      add :first_seen_at, :utc_datetime, null: false
      add :last_seen_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:customers, [:last_seen_at])
  end

  def down do
    drop_if_exists index(:customers, [:last_seen_at])
    drop table(:customers)
  end
end
