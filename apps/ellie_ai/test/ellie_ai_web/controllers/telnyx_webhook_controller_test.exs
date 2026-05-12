defmodule EllieAiWeb.TelnyxWebhookControllerTest do
  use EllieAiWeb.ConnCase, async: false

  alias EllieAi.{Groups, Orgs}
  alias EllieAi.Calls.CallRegistry
  alias EllieAi.Test.TelnyxSigningHelper

  # signature verification is unit-tested in EllieAi.Telnyx.SignatureTest;
  # here every request is signed with the dev test keypair (priv/dev/) so
  # the SignaturePlug accepts it. eng review F3 (2026-05-10) removed the
  # dev bypass — every test sends a real signature.
  #
  # async: false because we touch the application-level CallSupervisor
  # + CallRegistry. AudioBridge fails to start (no OPENAI_API_KEY in
  # test, the :ignore path), so CallTree boots with CallServer + VadGate.

  setup do
    # ensure no stray call trees from prior tests are still running.
    DynamicSupervisor.which_children(EllieAi.Calls.CallSupervisor)
    |> Enum.each(fn {_, pid, _, _} ->
      if is_pid(pid),
        do: DynamicSupervisor.terminate_child(EllieAi.Calls.CallSupervisor, pid)
    end)

    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(EllieAi.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    {:ok, group} = Groups.create(%{slug: "test-group", name: "Test"})

    {:ok, org} =
      Orgs.create(%{
        group_id: group.id,
        slug: "test-org",
        name: "Test Org",
        resto_base_url: "http://localhost:4000",
        resto_org_slug: "test-org",
        telnyx_phone_number: "+15555550100"
      })

    %{org: org}
  end

  describe "POST /telnyx/webhook" do
    test "200s and spawns a CallTree on call.initiated for a known number", %{
      conn: conn,
      org: org
    } do
      ccid = "test-#{System.unique_integer([:positive])}"

      body =
        Jason.encode!(%{
          "data" => %{
            "event_type" => "call.initiated",
            "payload" => %{
              "call_control_id" => ccid,
              "from" => "+14155550199",
              "to" => org.telnyx_phone_number
            }
          }
        })

      conn = signed_post(conn, body)
      assert response(conn, 200) == ""

      assert eventually(fn -> CallRegistry.whereis_call_server(ccid) end) != nil
    end

    test "200s without spawning when the dialed number doesn't match an org", %{conn: conn} do
      ccid = "test-#{System.unique_integer([:positive])}"

      body =
        Jason.encode!(%{
          "data" => %{
            "event_type" => "call.initiated",
            "payload" => %{
              "call_control_id" => ccid,
              "from" => "+14155550199",
              "to" => "+19999999999"
            }
          }
        })

      conn = signed_post(conn, body)
      assert response(conn, 200) == ""

      Process.sleep(50)
      assert CallRegistry.whereis_call_server(ccid) == nil
    end

    test "200s on unknown event types without crashing", %{conn: conn} do
      body =
        Jason.encode!(%{
          "data" => %{
            "event_type" => "call.machine.detection.ended",
            "payload" => %{"call_control_id" => "ignored"}
          }
        })

      conn = signed_post(conn, body)
      assert response(conn, 200) == ""
    end

    test "200s on malformed bodies without crashing", %{conn: conn} do
      body = Jason.encode!(%{"not" => "what telnyx sends"})
      conn = signed_post(conn, body)
      assert response(conn, 200) == ""
    end

    test "401s when the signature header is missing", %{conn: conn} do
      conn =
        conn
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> post(~p"/telnyx/webhook", "{}")

      assert response(conn, 401) == ""
    end

    test "401s when the signature is wrong", %{conn: conn} do
      conn =
        conn
        |> Plug.Conn.put_req_header("telnyx-signature-ed25519", Base.encode64(:crypto.strong_rand_bytes(64)))
        |> Plug.Conn.put_req_header("telnyx-timestamp", Integer.to_string(System.system_time(:second)))
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> post(~p"/telnyx/webhook", "{}")

      assert response(conn, 401) == ""
    end
  end

  defp signed_post(conn, body) do
    conn =
      Enum.reduce(TelnyxSigningHelper.headers_for(body), conn, fn {k, v}, acc ->
        Plug.Conn.put_req_header(acc, k, v)
      end)

    # post the raw signed body. the controller reads it via CacheBodyReader
    # exactly as a real webhook would.
    post(conn, ~p"/telnyx/webhook", body)
  end

  defp eventually(fun, attempts \\ 25)
  defp eventually(fun, 0), do: fun.()

  defp eventually(fun, attempts) do
    case fun.() do
      nil ->
        Process.sleep(10)
        eventually(fun, attempts - 1)

      result ->
        result
    end
  end
end
