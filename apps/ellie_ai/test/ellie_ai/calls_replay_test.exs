defmodule EllieAi.CallsReplayTest do
  use EllieAi.DataCase, async: false

  alias EllieAi.{Calls, Groups, Orgs}
  alias EllieAi.Calls.Constants
  alias EllieAi.Test.ReqStub

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

    ccid = "test-ccid-#{System.unique_integer([:positive])}"
    {:ok, _} = Calls.start_call(org.id, ccid, %{"from" => "+14155550111", "to" => "+14155550112"})
    call = Calls.get_by_ccid(ccid)

    %{org: org, ccid: ccid, call: call}
  end

  test "replay re-executes the tool and creates a new row pointing at the original",
       %{call: call} do
    Req.Test.stub(EllieAi.RestoClient, fn conn ->
      ReqStub.json(conn, "GET", "/api/orgs/seasons-sf/availability", 200, %{
        "date" => "2026-06-01",
        "tables" => []
      })
    end)

    {:ok, original} =
      Calls.start_tool_call(call.id, %{
        type: Constants.tool_call_type_midflight(),
        tool_name: "lookup_availability",
        arguments: %{"date" => "2026-06-01"},
        openai_call_id: "oai-1"
      })

    {:ok, original} = Calls.finish_tool_call(original.id, {:ok, %{tables: []}}, 5)

    {:ok, new_row} = Calls.replay_tool_call(original.id, nil)

    assert new_row.replayed_from_id == original.id
    assert new_row.status == "ok"
    assert new_row.tool_name == "lookup_availability"

    all = Calls.list_tool_calls(call.id)
    assert length(all) == 2
  end

  test "replay with overridden arguments uses the override", %{call: call} do
    test_pid = self()

    Req.Test.stub(EllieAi.RestoClient, fn conn ->
      ReqStub.assert_request(conn, "GET", "/api/orgs/seasons-sf/availability")
      send(test_pid, {:request, conn.query_string})

      ReqStub.json(conn, "GET", "/api/orgs/seasons-sf/availability", 200, %{
        "date" => "2026-07-15",
        "tables" => []
      })
    end)

    {:ok, original} =
      Calls.start_tool_call(call.id, %{
        type: Constants.tool_call_type_midflight(),
        tool_name: "lookup_availability",
        arguments: %{"date" => "2026-06-01"},
        openai_call_id: "oai-2"
      })

    {:ok, _new_row} = Calls.replay_tool_call(original.id, %{"date" => "2026-07-15"})

    assert_received {:request, qs}
    assert qs =~ "date=2026-07-15"
  end

  test "replay of unknown id returns :not_found" do
    assert {:error, :not_found} = Calls.replay_tool_call(Ecto.UUID.generate(), nil)
  end
end
