defmodule RestoBookingApp.Repo.Migrations.MakeReservationsTableStartsAtUnique do
  use Ecto.Migration

  def change do
    drop index(:reservations, [:table_id, :starts_at])
    # db-level backstop for the app overlap check; only catches exact
    # same-slot collisions, not partial overlaps.
    create unique_index(:reservations, [:table_id, :starts_at])
  end
end
