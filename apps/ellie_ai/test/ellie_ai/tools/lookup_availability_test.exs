defmodule EllieAi.Tools.LookupAvailabilityTest do
  use EllieAi.DataCase, async: false

  alias EllieAi.{Groups, Orgs}
  alias EllieAi.Tools.LookupAvailability

  setup do
    bypass = Bypass.open()
    base = "http://localhost:#{bypass.port}"

    {:ok, group} = Groups.upsert_by_slug("seasons", %{name: "Seasons"})

    {:ok, org} =
      Orgs.upsert_by_slug("seasons-sf", %{
        group_id: group.id,
        name: "Seasons SF",
        location: "San Francisco",
        time_zone: "America/Los_Angeles",
        resto_base_url: base,
        resto_org_slug: "seasons-sf"
      })

    %{bypass: bypass, org: org}
  end

  test "to_openai/1 shape", %{org: _} do
    defn = EllieAi.Tools.Tool.to_openai(LookupAvailability)
    assert defn.name == "lookup_availability"
    assert defn.parameters.required == ["date"]
  end

  test "happy path returns the body as-is", %{bypass: bypass, org: org} do
    Bypass.stub(bypass, "GET", "/api/orgs/seasons-sf/availability", fn conn ->
      conn |> Plug.Conn.put_resp_content_type("application/json") |> Plug.Conn.resp(200, ~s({"date":"2026-06-01","tables":[{"table_id":"t1","reservations":[]}]}))
    end)

    assert {:ok, %{"date" => "2026-06-01", "tables" => _}} =
             LookupAvailability.execute(%{"date" => "2026-06-01"}, %{org: org})
  end

  test "transient errors bubble", %{bypass: bypass, org: org} do
    Bypass.stub(bypass, "GET", "/api/orgs/seasons-sf/availability", fn conn ->
      Plug.Conn.resp(conn, 500, "boom")
    end)

    assert {:error, {:transient, _}} =
             LookupAvailability.execute(%{"date" => "2026-06-01"}, %{org: org})
  end

  test "missing date is permanent", %{org: org} do
    assert {:error, {:permanent, _}} = LookupAvailability.execute(%{}, %{org: org})
  end
end
