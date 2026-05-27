defmodule EllieAi.Tools.LookupAvailabilityTest do
  use EllieAi.DataCase, async: false

  alias EllieAi.{Groups, Orgs}
  alias EllieAi.Test.ReqStub
  alias EllieAi.Tools.LookupAvailability

  setup do
    {:ok, group} = Groups.upsert_by_slug("seasons", %{name: "Seasons"})

    {:ok, org} =
      Orgs.upsert_by_slug("seasons-sf", %{
        group_id: group.id,
        name: "Seasons SF",
        location: "San Francisco",
        time_zone: "America/Los_Angeles",
        resto_base_url: "https://resto.test",
        resto_org_slug: "seasons-sf"
      })

    %{org: org}
  end

  test "to_openai/1 shape", %{org: _} do
    defn = EllieAi.Tools.Tool.to_openai(LookupAvailability)
    assert defn.name == "lookup_availability"
    assert defn.parameters.required == ["date"]
  end

  test "happy path returns the body as-is", %{org: org} do
    Req.Test.stub(EllieAi.RestoClient, fn conn ->
      ReqStub.json(conn, "GET", "/api/orgs/seasons-sf/availability", 200, %{
        "date" => "2026-06-01",
        "tables" => [%{"table_id" => "t1", "reservations" => []}]
      })
    end)

    assert {:ok, %{"date" => "2026-06-01", "tables" => _}} =
             LookupAvailability.execute(%{"date" => "2026-06-01"}, %{org: org})
  end

  test "transient errors bubble", %{org: org} do
    Req.Test.stub(EllieAi.RestoClient, fn conn ->
      ReqStub.text(conn, "GET", "/api/orgs/seasons-sf/availability", 500, "boom")
    end)

    assert {:error, {:transient, _}} =
             LookupAvailability.execute(%{"date" => "2026-06-01"}, %{org: org})
  end

  test "missing date is permanent", %{org: org} do
    assert {:error, {:permanent, _}} = LookupAvailability.execute(%{}, %{org: org})
  end
end
