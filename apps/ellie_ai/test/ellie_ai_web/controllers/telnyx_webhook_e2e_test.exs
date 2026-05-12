defmodule EllieAiWeb.TelnyxWebhookE2ETest do
  @moduledoc """
  end-to-end happy path through the telnyx webhook surface, signed
  with the dev test keypair so the SignaturePlug accepts each request:

      call.initiated → call tree spawned, system_event recorded,
                       answer posted to telnyx (mocked via bypass)
      call.answered  → streaming_start posted, system_event recorded
      call.hangup    → call finished, system_event recorded

  the openai realtime ws is not started in this test (no
  OPENAI_API_KEY), so AudioBridge declines to start and its absence is
  the expected condition. that keeps the test deterministic without
  needing a real ws server. all other parts of the pipeline (telnyx
  http client + bypass, call_server, system_event recording) run for
  real.
  """

  use EllieAiWeb.ConnCase, async: false

  alias EllieAi.{Calls, Groups, Orgs}
  alias EllieAi.Test.TelnyxSigningHelper

  setup do
    DynamicSupervisor.which_children(EllieAi.Calls.CallSupervisor)
    |> Enum.each(fn {_, pid, _, _} ->
      if is_pid(pid),
        do: DynamicSupervisor.terminate_child(EllieAi.Calls.CallSupervisor, pid)
    end)

    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(EllieAi.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    telnyx_bypass = Bypass.open()
    base = "http://localhost:#{telnyx_bypass.port}"

    prev_telnyx = Application.get_env(:ellie_ai, EllieAi.Telnyx.Client, [])

    Application.put_env(:ellie_ai, EllieAi.Telnyx.Client,
      base_url: base,
      api_key: "test-key"
    )

    audio_dir =
      Path.join(System.tmp_dir!(), "ellie_e2e_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(audio_dir)
    Application.put_env(:ellie_ai, :audio_dir, audio_dir)

    on_exit(fn ->
      Application.put_env(:ellie_ai, EllieAi.Telnyx.Client, prev_telnyx)
      Application.delete_env(:ellie_ai, :audio_dir)
      File.rm_rf!(audio_dir)
    end)

    {:ok, group} = Groups.create(%{slug: "test-group-e2e-#{System.unique_integer([:positive])}", name: "Test"})

    {:ok, org} =
      Orgs.create(%{
        group_id: group.id,
        slug: "test-org-e2e-#{System.unique_integer([:positive])}",
        name: "Test Org",
        resto_base_url: "http://localhost:1",
        resto_org_slug: "test-org",
        telnyx_phone_number: "+15555550199"
      })

    %{telnyx: telnyx_bypass, org: org}
  end

  test "call.initiated → call.answered → call.hangup walks the lifecycle",
       %{conn: conn, telnyx: telnyx, org: org} do
    ccid = "ccid-e2e-#{System.unique_integer([:positive])}"

    test_pid = self()

    Bypass.stub(telnyx, "POST", "/v2/calls/#{ccid}/actions/answer", fn conn ->
      send(test_pid, {:telnyx, :answer})
      Plug.Conn.resp(conn, 200, ~s({"data":{}}))
    end)

    Bypass.stub(telnyx, "POST", "/v2/calls/#{ccid}/actions/streaming_start", fn conn ->
      send(test_pid, {:telnyx, :streaming_start})
      Plug.Conn.resp(conn, 200, ~s({"data":{}}))
    end)

    Bypass.stub(telnyx, "POST", "/v2/calls/#{ccid}/actions/hangup", fn conn ->
      send(test_pid, {:telnyx, :hangup})
      Plug.Conn.resp(conn, 200, ~s({"data":{}}))
    end)

    initiated_body =
      Jason.encode!(%{
        "data" => %{
          "event_type" => "call.initiated",
          "payload" => %{
            "call_control_id" => ccid,
            "from" => "+14155550100",
            "to" => org.telnyx_phone_number
          }
        }
      })

    conn1 = signed_post(conn, initiated_body)
    assert response(conn1, 200) == ""

    assert_receive {:telnyx, :answer}, 2000
    call = eventually(fn -> Calls.get_by_ccid(ccid) end)
    assert call
    assert call.status == "ringing"

    events = eventually_nonempty(fn ->
      Calls.list_system_events(call.id)
      |> Enum.filter(&(&1.kind == "telnyx.call.initiated"))
    end)

    assert events != []

    answered_body =
      Jason.encode!(%{
        "data" => %{
          "event_type" => "call.answered",
          "payload" => %{"call_control_id" => ccid}
        }
      })

    conn2 = signed_post(conn, answered_body)
    assert response(conn2, 200) == ""

    assert_receive {:telnyx, :streaming_start}, 2000

    answered_events =
      eventually_nonempty(fn ->
        Calls.list_system_events(call.id) |> Enum.filter(&(&1.kind == "telnyx.call.answered"))
      end)

    assert answered_events != []

    hangup_body =
      Jason.encode!(%{
        "data" => %{
          "event_type" => "call.hangup",
          "payload" => %{"call_control_id" => ccid, "hangup_cause" => "normal_clearing"}
        }
      })

    conn3 = signed_post(conn, hangup_body)
    assert response(conn3, 200) == ""

    final = eventually(fn ->
      c = Calls.get(call.id)
      if c && c.status == "ended", do: c, else: nil
    end)

    assert final.status == "ended"
    assert final.ended_at

    hangup_events =
      Calls.list_system_events(call.id) |> Enum.filter(&(&1.kind == "telnyx.call.hangup"))

    assert hangup_events != []
  end

  defp signed_post(conn, body) do
    conn =
      Enum.reduce(TelnyxSigningHelper.headers_for(body), conn, fn {k, v}, acc ->
        Plug.Conn.put_req_header(acc, k, v)
      end)

    post(conn, ~p"/telnyx/webhook", body)
  end

  defp eventually(fun, attempts \\ 50)
  defp eventually(fun, 0), do: fun.()

  defp eventually(fun, attempts) do
    case fun.() do
      nil ->
        Process.sleep(20)
        eventually(fun, attempts - 1)

      result ->
        result
    end
  end

  defp eventually_nonempty(fun, attempts \\ 50)
  defp eventually_nonempty(fun, 0), do: fun.()

  defp eventually_nonempty(fun, attempts) do
    case fun.() do
      [] ->
        Process.sleep(20)
        eventually_nonempty(fun, attempts - 1)

      result ->
        result
    end
  end
end
