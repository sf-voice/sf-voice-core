defmodule EllieAi.Orgs do
  @moduledoc """
  ellie-side orgs context. each org carries the resto integration
  config + the Telnyx phone number that maps inbound calls to it.
  """

  import Ecto.Query

  alias EllieAi.Orgs.Org
  alias EllieAi.Repo

  def list, do: Repo.all(Org)

  def get(id), do: Repo.get(Org, id)

  def get_by_slug(slug) when is_binary(slug), do: Repo.get_by(Org, slug: slug)

  @doc """
  normalizes the input to canonical E.164 first so a webhook payload of
  `+18774980043` matches an org stored canonically regardless of how the
  value was originally entered. defense-in-depth: `Org.changeset` already
  enforces canonical E.164 on write, but this keeps lookups robust against
  legacy rows or test fixtures that snuck in differently-formatted numbers.
  """
  def get_by_telnyx_number(number) when is_binary(number) do
    case normalize(number) do
      {:ok, e164} ->
        Repo.get_by(Org, telnyx_phone_number: e164) ||
          Repo.get_by(Org, telnyx_phone_number: number)

      :error ->
        Repo.get_by(Org, telnyx_phone_number: number)
    end
  end

  defp normalize(number) do
    case ExPhoneNumber.parse(number, "US") do
      {:ok, parsed} ->
        if ExPhoneNumber.Validation.is_possible_number?(parsed) do
          {:ok, ExPhoneNumber.format(parsed, :e164)}
        else
          :error
        end

      _ ->
        :error
    end
  end

  @doc """
  the reconciliation cron iterates this list — orgs missing config are
  skipped without an error.
  """
  def list_with_resto_config do
    from(o in Org,
      where:
        not is_nil(o.resto_base_url) and o.resto_base_url != "" and
          not is_nil(o.resto_org_slug) and o.resto_org_slug != ""
    )
    |> Repo.all()
  end

  def create(attrs) do
    %Org{}
    |> Org.changeset(attrs)
    |> Repo.insert()
  end

  # fields the /settings Org admin card may edit. excludes slug + group_id
  # — slug is a stable URL key and group_id is a wiring concern, neither
  # should be mutated from the staff UI.
  @admin_fields ~w(name location time_zone resto_base_url resto_org_slug telnyx_phone_number)a

  @doc """
  uses `Org.changeset/2` so telnyx normalization + format validations
  still fire, but ignores any attrs outside the admin allowlist.
  """
  def update_admin(%Org{} = org, attrs) do
    safe_attrs =
      attrs
      |> Enum.filter(fn {k, _} -> to_atom(k) in @admin_fields end)
      |> Map.new(fn {k, v} -> {to_atom(k), v} end)

    org
    |> Org.changeset(safe_attrs)
    |> Repo.update()
  end

  def admin_changeset(%Org{} = org, attrs \\ %{}) do
    Org.changeset(org, attrs)
  end

  defp to_atom(k) when is_atom(k), do: k
  defp to_atom(k) when is_binary(k), do: String.to_existing_atom(k)

  @doc "idempotent for seeds."
  def upsert_by_slug(slug, attrs) when is_binary(slug) do
    attrs = Map.put(attrs, :slug, slug)

    case get_by_slug(slug) do
      nil -> create(attrs)
      %Org{} = existing -> existing |> Org.changeset(attrs) |> Repo.update()
    end
  end
end
