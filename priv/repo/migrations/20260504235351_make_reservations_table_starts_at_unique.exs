defmodule RestoBookingApp.Repo.Migrations.MakeReservationsTableStartsAtUnique do
  use Ecto.Migration

  # backstop for the application-level overlap check: if two callers ever race
  # past the in-process check, the database refuses the second insert. only
  # catches exact same-slot collisions, not arbitrary partial overlaps — that's
  # why the app check still matters.

  def change do
    drop index(:reservations, [:table_id, :starts_at])
    create unique_index(:reservations, [:table_id, :starts_at])
  end
end
