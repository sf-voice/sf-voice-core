defmodule RestoBookingApp.Repo.Migrations.CreateReservations do
  use Ecto.Migration

  def change do
    create table(:reservations, primary_key: false) do
      # uuid as a string in sqlite — keeps the column human-readable
      add :id, :binary_id, primary_key: true
      add :cancel_token, :string, null: false
      add :table_id, :string, null: false
      add :starts_at, :utc_datetime, null: false
      add :ends_at, :utc_datetime, null: false
      add :name, :string, null: false
      add :dietary, :string

      timestamps(type: :utc_datetime)
    end

    # the overlap query filters by table_id then sorts by time, so this is the
    # right composite to keep it cheap as the table grows
    create index(:reservations, [:table_id, :starts_at])
  end
end
