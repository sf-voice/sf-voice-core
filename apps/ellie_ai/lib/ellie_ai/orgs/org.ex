defmodule EllieAi.Orgs.Org do
  @moduledoc """

  """

  use Ecto.Schema
  import Ecto.Changeset

  alias EllieAi.Customers.CustomerSummary
  alias EllieAi.Groups.Group
  alias EllieAi.Menu.MenuItem
  alias EllieAi.Prompts.Prompt
  alias EllieAi.Settings.Setting

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @slug_regex ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/

  @default_phone_region "US"

  schema "orgs" do
    field :slug, :string
    field :name, :string
    field :location, :string
    field :time_zone, :string, default: "America/Los_Angeles"

    field :resto_base_url, :string
    field :resto_org_slug, :string

    field :telnyx_phone_number, :string

    belongs_to :group, Group
    has_many :customer_summaries, CustomerSummary
    has_many :menu_items, MenuItem
    has_many :prompts, Prompt
    has_many :settings, Setting

    timestamps(type: :utc_datetime)
  end

  @creatable ~w(group_id slug name location time_zone resto_base_url
                resto_org_slug telnyx_phone_number)a
  @required ~w(group_id slug name resto_base_url resto_org_slug)a

  def changeset(org, attrs) do
    org
    |> cast(attrs, @creatable)
    |> validate_required(@required)
    |> validate_format(:slug, @slug_regex)
    |> validate_format(:resto_org_slug, @slug_regex)
    |> validate_telnyx()
    |> unique_constraint(:slug)
    |> unique_constraint(:telnyx_phone_number)
    |> assoc_constraint(:group)
  end

  # telnyx number is optional in the schema (an org may exist before the
  # number is provisioned), but if set it must parse as a real phone
  # number per libphonenumber. we normalize to canonical E.164 here so
  # the column always matches what telnyx will send on inbound webhooks
  # — fixes the class of bug where someone stored `+8774980043` (missing
  # the US country code) instead of `+18774980043`.
  defp validate_telnyx(changeset) do
    case get_field(changeset, :telnyx_phone_number) do
      nil ->
        changeset

      "" ->
        put_change(changeset, :telnyx_phone_number, nil)

      raw ->
        normalize_or_reject(changeset, raw)
    end
  end

  defp normalize_or_reject(changeset, raw) do
    case ExPhoneNumber.parse(raw, @default_phone_region) do
      {:ok, parsed} ->
        if ExPhoneNumber.Validation.is_possible_number?(parsed) do
          put_change(changeset, :telnyx_phone_number, ExPhoneNumber.format(parsed, :e164))
        else
          add_error(
            changeset,
            :telnyx_phone_number,
            "is not a plausible phone number (got #{inspect(raw)})"
          )
        end

      {:error, reason} ->
        add_error(
          changeset,
          :telnyx_phone_number,
          "couldn't parse #{inspect(raw)}: #{inspect(reason)}"
        )
    end
  end
end
