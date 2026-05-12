defmodule RestoBookingApp.Repo.Migrations.MultiTenantOrgs do
  use Ecto.Migration

  def up do
    create table(:orgs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :slug, :string, null: false
      add :name, :string, null: false
      add :location, :string
      # IANA tz; used by Tz to localize "today" in ellie's prompts.
      add :time_zone, :string, null: false, default: "America/Los_Angeles"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:orgs, [:slug])

    create table(:tables, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :org_id, references(:orgs, type: :binary_id, on_delete: :delete_all), null: false
      # slug is what the api + legacy reservations.table_id reference (e.g. "T1").
      add :slug, :string, null: false
      add :seats, :integer, null: false
      add :shape, :string, null: false
      add :x, :integer, null: false
      add :y, :integer, null: false
      add :sort_order, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tables, [:org_id, :slug])
    create index(:tables, [:org_id])

    create table(:menu_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :org_id, references(:orgs, type: :binary_id, on_delete: :delete_all), null: false
      add :service, :string, null: false
      add :name, :string, null: false
      add :price_cents, :integer, null: false
      # csv string; array semantics live at the schema-cast layer.
      add :dietary, :string, null: false, default: ""
      add :sort_order, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:menu_items, [:org_id, :service])

    # destructive — sqlite can't ALTER ADD NOT NULL without a default.
    execute("DELETE FROM reservations")
    execute("DELETE FROM contacts")
    execute("DELETE FROM customers")

    alter table(:customers) do
      # restrict: a customer with reservations should never be silently orphaned.
      add :org_id, references(:orgs, type: :binary_id, on_delete: :restrict), null: false
    end

    create index(:customers, [:org_id])

    alter table(:contacts) do
      add :org_id, references(:orgs, type: :binary_id, on_delete: :restrict), null: false
    end

    create index(:contacts, [:org_id])

    alter table(:reservations) do
      add :org_id, references(:orgs, type: :binary_id, on_delete: :restrict), null: false
    end

    create index(:reservations, [:org_id])

    # no-overlap becomes per-org so two orgs can both book "T1" at the same time.
    drop_if_exists unique_index(:reservations, [:table_id, :starts_at],
                     name: :reservations_table_id_starts_at_index
                   )

    create unique_index(:reservations, [:org_id, :table_id, :starts_at],
             name: :reservations_org_id_table_id_starts_at_index
           )

    # same phone/email can exist once per org, not once globally.
    drop_if_exists unique_index(:contacts, [:kind, :value], name: :contacts_kind_value_index)
    create unique_index(:contacts, [:org_id, :kind, :value])
  end

  def down do
    drop_if_exists unique_index(:contacts, [:org_id, :kind, :value])
    create unique_index(:contacts, [:kind, :value])

    alter table(:reservations) do
      remove :org_id
    end

    drop_if_exists index(:contacts, [:org_id])

    alter table(:contacts) do
      remove :org_id
    end

    drop_if_exists index(:customers, [:org_id])

    alter table(:customers) do
      remove :org_id
    end

    drop_if_exists index(:menu_items, [:org_id, :service])
    drop table(:menu_items)

    drop_if_exists unique_index(:tables, [:org_id, :slug])
    drop_if_exists index(:tables, [:org_id])
    drop table(:tables)

    drop_if_exists unique_index(:orgs, [:slug])
    drop table(:orgs)
  end
end
