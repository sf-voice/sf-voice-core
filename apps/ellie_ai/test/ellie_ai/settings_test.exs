defmodule EllieAi.SettingsTest do
  use EllieAi.DataCase, async: false

  alias EllieAi.{Groups, Orgs, Settings}

  setup do
    {:ok, group} = Groups.upsert_by_slug("seasons-#{System.unique_integer([:positive])}", %{name: "S"})

    {:ok, org} =
      Orgs.upsert_by_slug("settings-org-#{System.unique_integer([:positive])}", %{
        group_id: group.id,
        name: "Test",
        location: "SF",
        time_zone: "America/Los_Angeles",
        resto_base_url: "http://localhost:1",
        resto_org_slug: "x"
      })

    :ets.whereis(:ellie_settings_cache) != :undefined &&
      :ets.delete_all_objects(:ellie_settings_cache)

    %{org: org}
  end

  test "get_value returns default on miss and caches", %{org: org} do
    assert "fallback" == Settings.get_value(org.id, "nonexistent", "fallback")
    assert "fallback" == Settings.get_value(org.id, "nonexistent", "fallback")
  end

  test "put invalidates the cache so subsequent get_value sees the new value", %{org: org} do
    assert nil == Settings.get_value(org.id, "k1")
    {:ok, _} = Settings.put(org.id, "k1", "first", value_type: "string")
    assert "first" == Settings.get_value(org.id, "k1")

    {:ok, _} = Settings.put(org.id, "k1", "second", value_type: "string")
    assert "second" == Settings.get_value(org.id, "k1")
  end
end
