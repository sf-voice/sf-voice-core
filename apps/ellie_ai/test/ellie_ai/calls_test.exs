defmodule EllieAi.CallsTest do
  use ExUnit.Case, async: false

  alias EllieAi.{Calls, Groups, Orgs}
  alias EllieAi.Calls.{CallRegistry, CallServer}

  # exercises the per-call supervision tree end-to-end. async: false
  # because the CallSupervisor + CallRegistry are application-global.
  #
  # uses sandbox shared mode so the spawned CallTree (running in a
  # different process) sees the org row this test inserts.
  #
  # AudioBridge is swapped for a local stub in test, which keeps these
  # supervision checks from opening an OpenAI websocket.

  setup do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(EllieAi.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    on_exit(fn ->
      DynamicSupervisor.which_children(EllieAi.Calls.CallSupervisor)
      |> Enum.each(fn {_, p, _, _} ->
        if is_pid(p),
          do: DynamicSupervisor.terminate_child(EllieAi.Calls.CallSupervisor, p)
      end)
    end)

    {:ok, group} = Groups.create(%{slug: "test-group", name: "Test"})

    {:ok, org} =
      Orgs.create(%{
        group_id: group.id,
        slug: "test-org-#{System.unique_integer([:positive])}",
        name: "Test Org",
        resto_base_url: "http://localhost:4000",
        resto_org_slug: "test-org"
      })

    %{org: org}
  end

  describe "spawn_or_noop/3" do
    test "starts a CallTree, registers a CallServer, persists a calls row", %{org: org} do
      ccid = "test-ccid-#{System.unique_integer([:positive])}"

      assert {:ok, pid} = Calls.spawn_or_noop(org, ccid, %{"from" => "+1", "to" => "+2"})
      assert is_pid(pid)
      assert pid == CallRegistry.whereis_call_server(ccid)
      assert Process.alive?(pid)

      # the row should exist with status "ringing".
      call = Calls.get_by_ccid(ccid)
      assert call != nil
      assert call.status == "ringing"
      assert call.from_phone == "+1"
      assert call.to_phone == "+2"
    end

    test "second call with same ccid is a no-op (returns same pid, single row)", %{org: org} do
      ccid = "test-ccid-#{System.unique_integer([:positive])}"

      {:ok, pid1} = Calls.spawn_or_noop(org, ccid, %{})
      {:ok, pid2} = Calls.spawn_or_noop(org, ccid, %{})

      assert pid1 == pid2
      # only one row: idempotent insert.
      calls = Calls.list_recent(org.id)
      assert length(Enum.filter(calls, &(&1.provider_id == ccid))) == 1
    end

    test "shutdown stops the CallServer", %{org: org} do
      ccid = "test-ccid-#{System.unique_integer([:positive])}"

      {:ok, pid} = Calls.spawn_or_noop(org, ccid, %{})
      ref = Process.monitor(pid)

      CallServer.shutdown(pid)

      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1_000
    end
  end

  describe "lifecycle persistence" do
    test "on_hangup updates status to ended and sets ended_at", %{org: org} do
      ccid = "test-ccid-#{System.unique_integer([:positive])}"

      {:ok, _} = Calls.spawn_or_noop(org, ccid, %{})
      Calls.on_hangup(ccid)

      # let the cast propagate.
      Process.sleep(50)

      call = Calls.get_by_ccid(ccid)
      assert call.status == "ended"
      assert call.ended_at != nil
    end

    test "append_turn writes a transcript_turn row scoped to the call", %{org: org} do
      ccid = "test-ccid-#{System.unique_integer([:positive])}"

      {:ok, _} = Calls.spawn_or_noop(org, ccid, %{})

      assert {:ok, _} = Calls.append_turn(ccid, "user", "hello")
      assert {:ok, _} = Calls.append_turn(ccid, "assistant", "hi there")

      call = Calls.get(Calls.get_by_ccid(ccid).id)
      assert length(call.transcript_turns) == 2
      assert Enum.map(call.transcript_turns, & &1.role) == ["user", "assistant"]
    end

    test "append_turn returns {:error, :no_call} when ccid is unknown" do
      assert {:error, :no_call} = Calls.append_turn("nope", "user", "hi")
    end
  end

  describe "tool_calls persistence" do
    setup %{org: org} do
      ccid = "test-ccid-#{System.unique_integer([:positive])}"
      {:ok, _pid} = Calls.spawn_or_noop(org, ccid, %{})
      call = Calls.get_by_ccid(ccid)
      %{call: call}
    end

    test "start_tool_call inserts a pending row with the type + tool_name", %{call: call} do
      assert {:ok, tc} =
               Calls.start_tool_call(call.id, %{
                 type: "midflight",
                 tool_name: "lookup_customer",
                 arguments: %{"phone" => "+14155550100"},
                 openai_call_id: "fc_abc123"
               })

      assert tc.status == "pending"
      assert tc.type == "midflight"
      assert tc.tool_name == "lookup_customer"
      assert tc.arguments == %{"phone" => "+14155550100"}
      assert tc.openai_call_id == "fc_abc123"
      assert tc.result == nil
      assert tc.duration_ms == nil
    end

    test "before-type tool_call doesn't need an openai_call_id", %{call: call} do
      assert {:ok, tc} =
               Calls.start_tool_call(call.id, %{
                 type: "before",
                 tool_name: "lookup_customer",
                 arguments: %{"phone" => "+14155550100"}
               })

      assert tc.type == "before"
      assert tc.openai_call_id == nil
    end

    test "rejects an invalid type", %{call: call} do
      assert {:error, cs} =
               Calls.start_tool_call(call.id, %{
                 type: "whenever",
                 tool_name: "x",
                 arguments: %{}
               })

      assert Keyword.has_key?(cs.errors, :type)
    end

    test "finish_tool_call(ok, ...) records result, status=ok, duration_ms", %{call: call} do
      {:ok, tc} =
        Calls.start_tool_call(call.id, %{
          type: "midflight",
          tool_name: "lookup_customer",
          arguments: %{},
          openai_call_id: "fc_x"
        })

      assert {:ok, updated} =
               Calls.finish_tool_call(tc.id, {:ok, %{"name" => "Ada"}}, 42)

      assert updated.status == "ok"
      assert updated.result == %{"name" => "Ada"}
      assert updated.duration_ms == 42
      assert updated.error == nil
    end

    test "finish_tool_call(error, ...) records error string + status=error", %{call: call} do
      {:ok, tc} =
        Calls.start_tool_call(call.id, %{
          type: "midflight",
          tool_name: "lookup_customer",
          arguments: %{},
          openai_call_id: "fc_y"
        })

      assert {:ok, updated} =
               Calls.finish_tool_call(tc.id, {:error, "tool timed out"}, 5000)

      assert updated.status == "error"
      assert updated.error == "tool timed out"
      assert updated.result == nil
      assert updated.duration_ms == 5000
    end

    test "finish_tool_call returns {:error, :not_found} for an unknown id" do
      assert {:error, :not_found} =
               Calls.finish_tool_call(Ecto.UUID.generate(), {:ok, %{}}, 0)
    end

    test "list_tool_calls returns rows in insertion order for the given call", %{call: call} do
      {:ok, a} = Calls.start_tool_call(call.id, %{type: "before", tool_name: "a", arguments: %{}})

      {:ok, b} =
        Calls.start_tool_call(call.id, %{type: "midflight", tool_name: "b", arguments: %{}})

      {:ok, c} = Calls.start_tool_call(call.id, %{type: "after", tool_name: "c", arguments: %{}})

      ids = Calls.list_tool_calls(call.id) |> Enum.map(& &1.id)
      assert ids == [a.id, b.id, c.id]
    end

    test "get_tool_call_by_openai_id finds the pending row", %{call: call} do
      {:ok, tc} =
        Calls.start_tool_call(call.id, %{
          type: "midflight",
          tool_name: "x",
          arguments: %{},
          openai_call_id: "fc_unique_42"
        })

      found = Calls.get_tool_call_by_openai_id("fc_unique_42")
      assert found.id == tc.id
    end
  end
end
