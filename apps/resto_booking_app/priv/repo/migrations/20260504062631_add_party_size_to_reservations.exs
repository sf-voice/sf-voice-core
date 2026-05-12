defmodule RestoBookingApp.Repo.Migrations.AddPartySizeToReservations do
  use Ecto.Migration

  def change do
    alter table(:reservations) do
      # default 1 backfills pre-existing rows so NOT NULL holds.
      add :party_size, :integer, null: false, default: 1
    end
  end
end
