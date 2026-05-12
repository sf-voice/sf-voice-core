defmodule EllieAi.Tools.RequestHumanHandoffTest do
  use EllieAi.DataCase, async: false

  alias EllieAi.{Calls, Groups, Orgs, Settings}
  alias EllieAi.Tools.RequestHumanHandoff

  setup do
    bypass = Bypass.open()
    base = "http://localhost:#{bypass.port}"

    prev_telnyx = Application.get_env(:ellie_ai, EllieAi.Telnyx.Client, [])

    Application.put_env(:ellie_ai, EllieAi.Telnyx.Client,
      base_url: base,
      api_key: "test-key"
    )

    System.put_env("TELNYX_CONNECTION_ID", "test-conn")
    System.put_env("NGROK_URL", "https://example.test")

    on_exit(fn ->
      Application.put_env(:ellie_ai, EllieAi.Telnyx.Client, prev_telnyx)
      System.delete_env("TELNYX_CONNECTION_ID")
      System.delete_env("NGROK_URL")
    end)

    {:ok, group} = Groups.upsert_by_slug("seasons", %{name: "Seasons"})

    {:ok, org} =
      Orgs.upsert_by_slug("seasons-sf-h-#{System.unique_integer([:positive])}", %{
        group_id: group.id,
        name: "Seasons SF",
        location: "San Francisco",
        time_zone: "America/Los_Angeles",
        resto_base_url: base,
        resto_org_slug: "seasons-sf",
        telnyx_phone_number: "+14155550199"
      })

    Settings.put(org.id, "staff_phone_e164", "+14155550100")

    ccid = "ccid-h-#{System.unique_integer([:positive])}"
    {:ok, _} = Calls.start_call(org.id, ccid, %{"from" => "+14155550101", "to" => org.telnyx_phone_number})

    %{bypass: bypass, org: org, ccid: ccid}
  end

  test "to_openai/1 shape" do
    defn = EllieAi.Tools.Tool.to_openai(RequestHumanHandoff)
    assert defn.name == "request_human_handoff"
    assert defn.parameters.required == []
  end

  test "dials staff and records dialing event", %{bypass: bypass, org: org, ccid: ccid} do
    test_pid = self()

    Bypass.stub(bypass, "POST", "/v2/calls", fn conn ->
      send(test_pid, :dialed)

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, ~s({"data":{"call_control_id":"staff-leg-123"}}))
    end)

    assert {:ok, %{escalating: true}} =
             RequestHumanHandoff.execute(%{"reason" => "asked for human"}, %{org: org, ccid: ccid})

    assert_receive :dialed, 2000

    call = Calls.get_by_ccid(ccid)
    events = Calls.list_system_events(call.id)
    assert Enum.any?(events, &(&1.kind == "escalator.dialing"))
  end

  test "missing telnyx config surfaces a permanent error", %{org: org, ccid: ccid} do
    System.delete_env("TELNYX_CONNECTION_ID")

    assert {:error, {:permanent, _}} =
             RequestHumanHandoff.execute(%{}, %{org: org, ccid: ccid})
  end
end
