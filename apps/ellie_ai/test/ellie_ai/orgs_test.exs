defmodule EllieAi.OrgsTest do
  @moduledoc """
  focused on the telnyx_phone_number normalization path. the rest of
  Orgs is exercised indirectly by webhook + liveview tests.
  """

  use EllieAi.DataCase, async: false

  alias EllieAi.{Groups, Orgs}

  setup do
    {:ok, group} = Groups.create(%{slug: "g-#{System.unique_integer([:positive])}", name: "G"})
    %{group: group}
  end

  defp base_attrs(group, extra \\ %{}) do
    Map.merge(
      %{
        group_id: group.id,
        slug: "o-#{System.unique_integer([:positive])}",
        name: "Test Org",
        resto_base_url: "http://localhost:4000",
        resto_org_slug: "test-org"
      },
      extra
    )
  end

  describe "telnyx_phone_number normalization on insert" do
    test "stores already-canonical E.164 unchanged", %{group: group} do
      assert {:ok, org} =
               Orgs.create(base_attrs(group, %{telnyx_phone_number: "+18774980043"}))

      assert org.telnyx_phone_number == "+18774980043"
    end

    test "rewrites a national-only US number to canonical E.164", %{group: group} do
      assert {:ok, org} =
               Orgs.create(base_attrs(group, %{telnyx_phone_number: "8774980043"}))

      assert org.telnyx_phone_number == "+18774980043"
    end

    test "rejects a number with an invalid country-code prefix (regression for the +8774980043 bug)",
         %{group: group} do
      # `+8` isn't an assigned country code prefix. before this change,
      # the schema's loose regex let this through; the call would land
      # with `to=+18774980043` from telnyx and fail to match the org.
      assert {:error, changeset} =
               Orgs.create(base_attrs(group, %{telnyx_phone_number: "+8774980043"}))

      assert %{telnyx_phone_number: [msg]} = errors_on(changeset)
      # ExPhoneNumber rejects this at parse time (no `+8` country code)
      # rather than later via is_possible_number?. either error message
      # is acceptable — both block the invalid value, which is the point.
      assert msg =~ "couldn't parse" or msg =~ "not a plausible phone number"
    end

    test "rejects an unparseable string", %{group: group} do
      assert {:error, changeset} =
               Orgs.create(base_attrs(group, %{telnyx_phone_number: "abc"}))

      assert %{telnyx_phone_number: [msg]} = errors_on(changeset)
      assert msg =~ "couldn't parse"
    end

    test "allows nil (org may exist before number provisioning)", %{group: group} do
      assert {:ok, org} = Orgs.create(base_attrs(group))
      assert org.telnyx_phone_number == nil
    end

    test "treats empty string as nil", %{group: group} do
      assert {:ok, org} =
               Orgs.create(base_attrs(group, %{telnyx_phone_number: ""}))

      assert org.telnyx_phone_number == nil
    end
  end

  describe "get_by_telnyx_number/1" do
    test "matches canonical E.164 from telnyx webhook against canonical row", %{group: group} do
      {:ok, org} = Orgs.create(base_attrs(group, %{telnyx_phone_number: "+18774980043"}))
      assert Orgs.get_by_telnyx_number("+18774980043").id == org.id
    end

    test "matches even when input is national-only (normalizes both sides)", %{group: group} do
      {:ok, org} = Orgs.create(base_attrs(group, %{telnyx_phone_number: "+18774980043"}))
      assert Orgs.get_by_telnyx_number("8774980043").id == org.id
    end

    test "returns nil for an unknown number", %{group: group} do
      {:ok, _} = Orgs.create(base_attrs(group, %{telnyx_phone_number: "+18774980043"}))
      assert Orgs.get_by_telnyx_number("+19999999999") == nil
    end
  end
end
