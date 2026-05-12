defmodule EllieAi.Evals.PromptRunnerTest do
  @moduledoc """
  unit-tests the runner's wiring against a bypass-mocked openai
  endpoint. proves the suite walks every case, scores responses, and
  averages them. the `:llm_eval` test in `eval_suite_test.exs` is the
  hot version that hits real openai — that one is opt-in.
  """

  use ExUnit.Case, async: false

  alias EllieAi.Evals.PromptRunner

  setup do
    bypass = Bypass.open()
    base = "http://localhost:#{bypass.port}"

    prev = Application.get_env(:ellie_ai, PromptRunner, [])
    Application.put_env(:ellie_ai, PromptRunner, base_url: base)
    System.put_env("OPENAI_API_KEY", "test-key")

    on_exit(fn ->
      Application.put_env(:ellie_ai, PromptRunner, prev)
      System.delete_env("OPENAI_API_KEY")
    end)

    %{bypass: bypass}
  end

  test "scores every case and averages them", %{bypass: bypass} do
    counter = :counters.new(1, [:atomics])

    Bypass.stub(bypass, "POST", "/v1/chat/completions", fn conn ->
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
      Plug.Conn.resp(conn, 200, content)
      |> Plug.Conn.put_resp_content_type("application/json")
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
