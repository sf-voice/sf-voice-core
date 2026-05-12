defmodule EllieAi.Prompts.EvalSuiteTest do
  @moduledoc """
  scaffolding for the 20-case llm eval suite (design review OV-6). the
  cases live in `priv/evals/cases.exs` so operators can review + edit
  them without touching test code.

  the actual openai-driven assertion path is tagged `:llm_eval` so the
  default `mix test` run doesn't burn tokens. CI invokes it explicitly
  via `mix test --only llm_eval` against a non-prod openai key.

  the always-on portion of this test verifies the case list itself is
  structurally valid: 20 entries, no duplicate ids, every `expects`
  list non-empty. this gives us a regression net even without spending
  on a real eval run.
  """

  use ExUnit.Case, async: true

  @cases_path Path.expand("../../../priv/evals/cases.exs", __DIR__)

  setup do
    cases =
      @cases_path
      |> Code.eval_file()
      |> elem(0)

    {:ok, cases: cases}
  end

  test "the eval suite has 20 cases", %{cases: cases} do
    assert length(cases) == 20
  end

  test "every case has a unique id 1..20", %{cases: cases} do
    ids = Enum.map(cases, & &1.id)
    assert Enum.sort(ids) == Enum.to_list(1..20)
  end

  test "every case has a non-empty label, input, and expects list", %{cases: cases} do
    for c <- cases do
      assert is_binary(c.label) and c.label != ""
      assert is_binary(c.input) and c.input != ""
      assert is_list(c.expects) and c.expects != []
    end
  end

  test "the prompt-injection case is present (defensive regression)", %{cases: cases} do
    assert Enum.any?(cases, &(&1.label == "prompt-injection"))
  end

  @tag :llm_eval
  @tag timeout: :timer.minutes(5)
  test "20-case suite averages ≥ 0.8 against the production prompt", %{cases: cases} do
    result = EllieAi.Evals.PromptRunner.run()

    assert length(result.cases) == length(cases)

    # surface failing cases in the test report so operators see WHICH
    # expectations missed without re-running the suite.
    failing =
      result.cases
      |> Enum.filter(&(&1.score < 0.6))
      |> Enum.map(fn c ->
        "  #{c.id} #{c.label} (score #{Float.round(c.score, 2)})"
      end)
      |> Enum.join("\n")

    if failing != "", do: IO.puts("\nfailing eval cases:\n" <> failing)

    assert result.average_score >= 0.8,
           "average eval score #{Float.round(result.average_score, 2)} below threshold 0.8"
  end
end
