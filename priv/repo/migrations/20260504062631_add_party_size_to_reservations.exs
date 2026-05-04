defmodule RestoBookingApp.Repo.Migrations.AddPartySizeToReservations do
  use Ecto.Migration

  def change do
    # default 1 backfills any seeded rows from before this column existed
    alter table(:reservations) do
      add :party_size, :integer, null: false, default: 1
    end
  end
end
