defmodule EllieAi.Repo.Migrations.MultiTenantOrgs do
  use Ecto.Migration

  def up do
    create table(:groups, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :slug, :string, null: false
      add :name, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:groups, [:slug])

    create table(:orgs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :group_id, references(:groups, type: :binary_id, on_delete: :restrict), null: false
      add :slug, :string, null: false
      add :name, :string, null: false
      add :location, :string
      add :time_zone, :string, null: false, default: "America/Los_Angeles"

      add :resto_base_url, :string, null: false
      add :resto_org_slug, :string, null: false

      add :telnyx_phone_number, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:orgs, [:slug])
    create unique_index(:orgs, [:telnyx_phone_number])
    create index(:orgs, [:group_id])


    create table(:prompts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :org_id, references(:orgs, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :body, :text, null: false
      add :version, :integer, null: false, default: 1
      add :active, :boolean, null: false, default: false
      add :created_by, :string

      timestamps(type: :utc_datetime)
    end

    create index(:prompts, [:org_id])
    create index(:prompts, [:org_id, :active])

   create table(:settings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :org_id, references(:orgs, type: :binary_id, on_delete: :delete_all), null: false
      add :key, :string, null: false
      add :value, :string
      add :value_type, :string, null: false, default: "string"
      add :description, :text
      add :surfaced, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:settings, [:org_id, :key])


    create table(:menu_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :org_id, references(:orgs, type: :binary_id, on_delete: :delete_all), null: false
      add :service, :string, null: false
      add :name, :string, null: false
      add :price_cents, :integer, null: false
      add :dietary, :string, null: false, default: ""
      add :sort_order, :integer, null: false, default: 0
      add :last_synced_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:menu_items, [:org_id, :service])
    create unique_index(:menu_items, [:org_id, :service, :name])

    execute("DELETE FROM customer_summary")

    drop_if_exists unique_index(:customer_summary, [:phone_e164])

    alter table(:customer_summary) do
      add :org_id, references(:orgs, type: :binary_id, on_delete: :delete_all), null: false
    end

    create index(:customer_summary, [:org_id])
    create unique_index(:customer_summary, [:org_id, :phone_e164])
  end

  def down do
    drop_if_exists unique_index(:customer_summary, [:org_id, :phone_e164])
    drop_if_exists index(:customer_summary, [:org_id])

    alter table(:customer_summary) do
      remove :org_id
    end

    create unique_index(:customer_summary, [:phone_e164])

    drop_if_exists unique_index(:menu_items, [:org_id, :service, :name])
    drop_if_exists index(:menu_items, [:org_id, :service])
    drop table(:menu_items)

    drop_if_exists unique_index(:settings, [:org_id, :key])
    drop table(:settings)

    drop_if_exists index(:prompts, [:org_id, :active])
    drop_if_exists index(:prompts, [:org_id])
    drop table(:prompts)

    drop_if_exists index(:orgs, [:group_id])
    drop_if_exists unique_index(:orgs, [:telnyx_phone_number])
    drop_if_exists unique_index(:orgs, [:slug])
    drop table(:orgs)

    drop_if_exists unique_index(:groups, [:slug])
    drop table(:groups)
  end
end
