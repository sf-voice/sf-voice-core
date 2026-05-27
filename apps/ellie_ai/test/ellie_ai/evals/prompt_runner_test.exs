defmodule EllieAi.Evals.PromptRunnerTest do
  @moduledoc """
  unit-tests the runner's wiring against a Req.Test-mocked openai
  endpoint. proves the suite walks every case, scores responses, and
  averages them. the `:llm_eval` test in `eval_suite_test.exs` is the
  hot version that hits real openai — that one is opt-in.
  """

  use ExUnit.Case, async: false

  alias EllieAi.Evals.PromptRunner
  alias EllieAi.Test.ReqStub

  setup do
    Req.Test.set_req_test_to_shared()
    Req.Test.verify_on_exit!()

    System.put_env("OPENAI_API_KEY", "test-key")

    on_exit(fn ->
      System.delete_env("OPENAI_API_KEY")
    end)

    :ok
  end

  test "scores every case and averages them" do
    counter = :counters.new(1, [:atomics])

    Req.Test.stub(PromptRunner, fn conn ->
      # alternate response: even calls are the assistant under test
      # (returns "ok"), odd calls are the scorer (returns 0.9).
      n = :counters.add(counter, 1, 1) || :counters.get(counter, 1)
      idx = :counters.get(counter, 1)

      content =
        if rem(idx, 2) == 1 do
          # assistant under test
          ~s({"id":"x","choices":[{"message":{"content":"ok"}}]})
        else
          # scorer
          ~s({"id":"x","choices":[{"message":{"content":"{\\"score\\":0.9,\\"matched\\":[\\"greeting\\"]}"}}]})
        end

      _ = n

      conn
      |> ReqStub.assert_request("POST", "/v1/chat/completions")
      |> Plug.Conn.put_status(200)
      |> Req.Test.json(Jason.decode!(content))
    end)

    result = PromptRunner.run()

    assert length(result.cases) == 20
    assert result.average_score == 0.9
    assert Enum.all?(result.cases, &is_binary(&1.response))
  end

  test "raises when OPENAI_API_KEY is missing" do
    System.delete_env("OPENAI_API_KEY")
    assert_raise RuntimeError, ~r/OPENAI_API_KEY missing/, fn -> PromptRunner.run() end
  end
end
