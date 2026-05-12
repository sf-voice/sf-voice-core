defmodule EllieAi.Calls.MemoryTest do
  use EllieAi.DataCase, async: false

  alias EllieAi.{Groups, Orgs, Settings}
  alias EllieAi.Calls.Memory

  setup do
    {:ok, group} = Groups.upsert_by_slug("mem-g-#{System.unique_integer([:positive])}", %{name: "G"})

    {:ok, org} =
      Orgs.upsert_by_slug("mem-o-#{System.unique_integer([:positive])}", %{
        group_id: group.id,
        name: "Test",
        location: "SF",
        time_zone: "America/Los_Angeles",
        resto_base_url: "http://localhost:1",
        resto_org_slug: "x"
      })

    # each test gets a fresh process context. the dict is process-local
    # but we still null it so a prior test's bootstrap can't bleed.
    Process.delete(:ellie_call_context)
    %{org: org}
  end

  test "returns nils when no context is in scope" do
    assert is_nil(Memory.org())
    assert is_nil(Memory.org_id())
    assert is_nil(Memory.ccid())
  end

  test "defaults when no context", _ctx do
    assert Memory.vad_silence_ms() == 700
    assert Memory.vad_mode() == "silero"
    assert Memory.sentiment_threshold() == 0.3
  end

  test "publish + bootstrap_from binds org + ccid to this process", %{org: org} do
    :ok = Memory.publish_context(org, "ccid-123")
    :ok = Memory.bootstrap_from("ccid-123")
    assert Memory.org().id == org.id
    assert Memory.org_id() == org.id
    assert Memory.ccid() == "ccid-123"
  end

  test "settings accessors read the org's actual values", %{org: org} do
    Settings.put(org.id, "vad_silence_ms", 900, value_type: "int")
    Settings.put(org.id, "sentiment_threshold", "0.45", value_type: "float")

    :ok = Memory.publish_context(org, "ccid-x")
    :ok = Memory.bootstrap_from("ccid-x")
    assert Memory.vad_silence_ms() == 900
    assert_in_delta Memory.sentiment_threshold(), 0.45, 0.001
  end

  test "Memory.async propagates context into the spawned task", %{org: org} do
    :ok = Memory.publish_context(org, "ccid-async")
    :ok = Memory.bootstrap_from("ccid-async")
    parent = self()

    {:ok, _pid} =
      Memory.async(fn ->
        send(parent, {:inside, Memory.org_id(), Memory.ccid()})
      end)

    assert_receive {:inside, oid, "ccid-async"}, 500
    assert oid == org.id
  end

  test "Memory.async with no parent context still runs the task" do
    parent = self()
    {:ok, _pid} = Memory.async(fn -> send(parent, {:inside, Memory.org_id()}) end)
    assert_receive {:inside, nil}, 500
  end
end
