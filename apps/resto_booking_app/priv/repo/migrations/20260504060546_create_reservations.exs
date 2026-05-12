defmodule RestoBookingApp.Repo.Migrations.CreateReservations do
  use Ecto.Migration

  def change do
    create table(:reservations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :cancel_token, :string, null: false
      add :table_id, :string, null: false
      add :starts_at, :utc_datetime, null: false
      add :ends_at, :utc_datetime, null: false
      add :name, :string, null: false
      add :dietary, :string

      timestamps(type: :utc_datetime)
    end

    # composite matches the overlap query's filter+sort shape.
    create index(:reservations, [:table_id, :starts_at])
  end
end
