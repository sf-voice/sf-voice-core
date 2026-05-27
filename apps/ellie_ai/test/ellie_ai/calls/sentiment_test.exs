defmodule EllieAi.Calls.SentimentTest do
  use EllieAi.DataCase, async: false

  alias EllieAi.{Calls, Groups, Orgs, Settings}
  alias EllieAi.Calls.{Sentiment, TranscriptTurn}
  alias EllieAi.Repo
  alias EllieAi.Test.ReqStub

  setup do
    System.put_env("OPENAI_API_KEY", "test-key")

    prev_telnyx = Application.get_env(:ellie_ai, EllieAi.Telnyx.Client, [])

    Application.put_env(
      :ellie_ai,
      EllieAi.Telnyx.Client,
      Keyword.put(prev_telnyx, :api_key, "test-key")
    )

    on_exit(fn ->
      Application.put_env(:ellie_ai, EllieAi.Telnyx.Client, prev_telnyx)
      System.delete_env("OPENAI_API_KEY")
    end)

    {:ok, group} = Groups.upsert_by_slug("s-#{System.unique_integer([:positive])}", %{name: "S"})

    {:ok, org} =
      Orgs.upsert_by_slug("sent-org-#{System.unique_integer([:positive])}", %{
        group_id: group.id,
        name: "Sent Org",
        location: "SF",
        time_zone: "America/Los_Angeles",
        resto_base_url: "http://localhost:1",
        resto_org_slug: "x",
        telnyx_phone_number: "+14155550100"
      })

    Settings.put(org.id, "sentiment_threshold", "0.3", value_type: "float")

    ccid = "ccid-sent-#{System.unique_integer([:positive])}"

    {:ok, _} =
      Calls.start_call(org.id, ccid, %{"from" => "+14155550101", "to" => org.telnyx_phone_number})

    %{org: org, ccid: ccid}
  end

  test "scores a user turn and updates the turn + call EMA", %{org: org, ccid: ccid} do
    Req.Test.stub(EllieAi.Providers.OpenAI, fn conn ->
      ReqStub.json(conn, "POST", "/v1/chat/completions", 200, %{
        "choices" => [%{"message" => %{"content" => ~s({"score":0.85})}}]
      })
    end)

    {:ok, turn} = Calls.append_turn(ccid, "user", "Yeah, that's great, thanks!")

    # bootstrap Memory in the test process — Sentiment.score_async will
    # propagate this context into the spawned task via Memory.async.
    :ok = EllieAi.Calls.Memory.publish_context(org, ccid)
    :ok = EllieAi.Calls.Memory.bootstrap_from(ccid)
    Sentiment.score_async(turn)

    # give task a moment
    Process.sleep(200)

    fresh = Repo.get(TranscriptTurn, turn.id)
    assert_in_delta fresh.sentiment_score, 0.85, 0.01

    call = Calls.get_by_ccid(ccid)
    assert is_float(call.sentiment_score)
  end

  test "score_async is a no-op on assistant turns", %{ccid: ccid} do
    {:ok, turn} = Calls.append_turn(ccid, "assistant", "I can help with that.")
    assert :ok == Sentiment.score_async(turn)
  end
end
