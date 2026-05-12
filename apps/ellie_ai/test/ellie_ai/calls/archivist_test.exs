defmodule EllieAi.Calls.ArchivistTest do
  use ExUnit.Case, async: false

  alias EllieAi.{Calls, Groups, Orgs}
  alias EllieAi.Calls.{Archivist, CallRegistry}

  # async: false — uses the application-global CallSupervisor + Registry.

  setup do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(EllieAi.Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    audio_dir = Path.join(System.tmp_dir!(), "ellie_archivist_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(audio_dir)
    Application.put_env(:ellie_ai, :audio_dir, audio_dir)

    on_exit(fn ->
      Application.delete_env(:ellie_ai, :audio_dir)
      File.rm_rf!(audio_dir)
    end)

    on_exit(fn ->
      DynamicSupervisor.which_children(EllieAi.Calls.CallSupervisor)
      |> Enum.each(fn {_, p, _, _} ->
        if is_pid(p),
          do: DynamicSupervisor.terminate_child(EllieAi.Calls.CallSupervisor, p)
      end)
    end)

    {:ok, group} = Groups.create(%{slug: "test-group-#{System.unique_integer([:positive])}", name: "Test"})

    {:ok, org} =
      Orgs.create(%{
        group_id: group.id,
        slug: "test-org-#{System.unique_integer([:positive])}",
        name: "Test Org",
        resto_base_url: "http://localhost:4000",
        resto_org_slug: "test-org"
      })

    %{org: org, audio_dir: audio_dir}
  end

  test "starts and accepts feeds, writes wav on terminate", %{org: org, audio_dir: audio_dir} do
    ccid = "ccid-#{System.unique_integer([:positive])}"
    {:ok, _} = Calls.start_call(org.id, ccid, %{"from" => "+10000000000", "to" => "+10000000001"})
    call = Calls.get_by_ccid(ccid)

    {:ok, pid} = Archivist.start_link(%{ccid: ccid})

    Archivist.feed_inbound(ccid, :binary.copy(<<0xFF>>, 800))
    Archivist.feed_outbound(ccid, :binary.copy(<<0x80>>, 800))

    # let casts flush
    :sys.get_state(pid)

    ref = Process.monitor(pid)
    GenServer.stop(pid, :normal)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}, 2000

    wav_path = Path.join([audio_dir, call.id, "full.wav"])
    assert File.exists?(wav_path)

    bin = File.read!(wav_path)
    assert <<"RIFF", _::little-32, "WAVE", _rest::binary>> = bin

    updated = Calls.get(call.id)
    assert updated.audio_duration_ms > 0
    # no aws creds in test → key stays nil
    assert is_nil(updated.audio_s3_key) or is_binary(updated.audio_s3_key)
  end

  test "ignores feeds when no call row exists" do
    ccid = "ghost-ccid-#{System.unique_integer([:positive])}"
    assert :ignore == Archivist.start_link(%{ccid: ccid})
    assert :ok == Archivist.feed_inbound(ccid, "noise")
    assert is_nil(CallRegistry.whereis_archivist(ccid))
  end
end
