defmodule RestoBookingApp.Repo.Migrations.ReplaceGuestFieldsOnReservations do
  use Ecto.Migration

  # cutover from a single `name` + `dietary` to the full booking-form fields.
  # we backfill so existing rows aren't lost: `name` is split on the first space
  # (close enough for demo data), and `notes` migrates over to `remarks`.
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

    # backfill from the old columns. instr returns 0 when there's no space, so
    # the case statement handles single-word names by stuffing everything into
    # first_name and leaving last_name blank.
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
