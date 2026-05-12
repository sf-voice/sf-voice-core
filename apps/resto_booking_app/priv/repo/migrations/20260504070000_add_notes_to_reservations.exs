defmodule RestoBookingApp.Repo.Migrations.AddNotesToReservations do
  use Ecto.Migration

  def change do
    alter table(:reservations) do
      add :notes, :text
    end
  end
end
