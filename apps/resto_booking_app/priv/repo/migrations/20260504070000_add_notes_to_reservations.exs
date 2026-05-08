defmodule RestoBookingApp.Repo.Migrations.AddNotesToReservations do
  use Ecto.Migration

  def change do
    # free-text notes from the guest — what they want to eat, occasion, etc.
    # nullable; existing rows backfill to nil.
    alter table(:reservations) do
      add :notes, :text
    end
  end
end
