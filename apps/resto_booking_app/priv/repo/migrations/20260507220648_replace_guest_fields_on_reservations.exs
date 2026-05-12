defmodule RestoBookingApp.Repo.Migrations.ReplaceGuestFieldsOnReservations do
  use Ecto.Migration

  def change do
    alter table(:reservations) do
      add :salutation, :string
      add :first_name, :string, null: false, default: ""
      add :last_name, :string, null: false, default: ""
      add :tel, :string, null: false, default: ""
      add :email, :string, null: false, default: ""
      add :special_requests, :string
      add :remarks, :string
    end

    # split old `name` on first space; single-word names land in first_name.
    execute(
      """
      UPDATE reservations
      SET first_name = CASE
            WHEN instr(name, ' ') > 0 THEN substr(name, 1, instr(name, ' ') - 1)
            ELSE name
          END,
          last_name = CASE
            WHEN instr(name, ' ') > 0 THEN substr(name, instr(name, ' ') + 1)
            ELSE ''
          END,
          remarks = notes
      """,
      "SELECT 1"
    )

    alter table(:reservations) do
      remove :name, :string
      remove :dietary, :string
      remove :notes, :string
    end
  end
end
