defmodule RestoBookingApp.Repo.Migrations.ReplaceGuestFieldsOnReservationsWithCustomerAndContact do
  use Ecto.Migration

  def up do
    # destructive cutover — no sensible backfill once guest fields split
    # into customers + contacts.
    execute("DELETE FROM reservations")

    alter table(:reservations) do
      remove :salutation
      remove :first_name
      remove :last_name
      remove :tel
      remove :email

      # restrict: never silently orphan a reservation if a customer is deleted.
      add :customer_id,
          references(:customers, type: :binary_id, on_delete: :restrict),
          null: false

      # nilify_all: deleting a contact falls back to the customer's preferred one.
      add :contact_id,
          references(:contacts, type: :binary_id, on_delete: :nilify_all),
          null: true
    end

    create index(:reservations, [:customer_id])
    create index(:reservations, [:contact_id])
  end

  def down do
    drop_if_exists index(:reservations, [:contact_id])
    drop_if_exists index(:reservations, [:customer_id])

    alter table(:reservations) do
      remove :contact_id
      remove :customer_id

      add :salutation, :string
      add :first_name, :string, null: false, default: ""
      add :last_name, :string, null: false, default: ""
      add :tel, :string, null: false, default: ""
      add :email, :string, null: false, default: ""
    end
  end
end
