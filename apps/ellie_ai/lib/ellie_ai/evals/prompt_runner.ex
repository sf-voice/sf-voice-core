defmodule EllieAi.Evals.PromptRunner do
  @moduledoc """

  """

  alias EllieAi.HttpClient
  alias EllieAi.Prompts.Defaults

  require Logger

  @model "gpt-4o"
  @scorer_model "gpt-4o-mini"
  @cases_path Path.expand("../../../priv/evals/cases.exs", __DIR__)

  @doc """
  run every case, score each response, return `%{cases: [...], average_score: 0..1}`.
  raises if OPENAI_API_KEY is missing.
  """
  @spec run() :: %{cases: [map()], average_score: float()}
  def run do
    unless openai_key(), do: raise("OPENAI_API_KEY missing")

    cases = load_cases()
    prompt = Defaults.fallback()

    scored =
      cases
      |> Enum.map(fn c ->
        with {:ok, response} <- chat_completion(prompt, c.input),
             {:ok, score} <- score_response(response, c.expects) do
          %{id: c.id, label: c.label, response: response, score: score}
        else
          {:error, reason} ->
            Logger.warning("eval case #{c.id} failed: #{inspect(reason)}")
            %{id: c.id, label: c.label, response: nil, score: 0.0, error: reason}
        end
      end)

    average =
      scored
      |> Enum.map(& &1.score)
      |> Enum.sum()
      |> Kernel./(length(scored))

    %{cases: scored, average_score: average}
  end

  defp load_cases do
    @cases_path |> Code.eval_file() |> elem(0)
  end

  # ── openai calls ───────────────────────────────────────────────────────

  defp chat_completion(system_prompt, user_input) do
    body = %{
      model: @model,
      messages: [
        %{role: "system", content: system_prompt},
        %{role: "user", content: user_input}
      ],
      temperature: 0.2
    }

    case post("/v1/chat/completions", body) do
      {:ok, %{"choices" => [%{"message" => %{"content" => content}} | _]}}
      when is_binary(content) ->
        {:ok, content}

      {:ok, other} ->
        {:error, {:bad_response, other}}

      {:error, _} = err ->
        err
    end
  end

  # score the assistant response against the list of expected behaviours.
  # the scorer model returns {"score": 0..1, "matched": ["greeting", ...]}
  # so we can show operators which expectations weren't met when a case fails.
  defp score_response(response, expects) when is_binary(response) and is_list(expects) do
    expectations = Enum.map_join(expects, ", ", &Atom.to_string/1)

    system = """
    You judge whether an assistant response satisfies a list of expected
    behaviours. Return ONLY a JSON object: {"score": 0..1, "matched": [...]}.
    Score = (count of matched expectations) / (total expectations). No prose.
    """

    user = """
    Expected behaviours: #{expectations}

    Assistant response:
    #{response}
    """

    body = %{
      model: @scorer_model,
      messages: [
        %{role: "system", content: system},
        %{role: "user", content: user}
      ],
      temperature: 0,
      response_format: %{type: "json_object"}
    }

    case post("/v1/chat/completions", body) do
      {:ok, %{"choices" => [%{"message" => %{"content" => json}} | _]}} ->
        parse_score(json)

      {:ok, other} ->
        {:error, {:bad_scorer_response, other}}

      {:error, _} = err ->
        err
    end
  end

  defp parse_score(json) do
    with {:ok, %{"score" => score}} when is_number(score) <- Jason.decode(json) do
      {:ok, clamp(score / 1)}
    else
      _ -> {:error, {:bad_score_json, json}}
    end
  end

  defp clamp(s) when s < 0.0, do: 0.0
  defp clamp(s) when s > 1.0, do: 1.0
  defp clamp(s), do: s

  defp post(path, body) do
    case Req.post(
           "#{base_url()}#{path}",
           HttpClient.request_options(__MODULE__,
             json: body,
             auth: {:bearer, openai_key()},
             receive_timeout: 30_000,
             retry: :transient,
             max_retries: 2
           )
         ) do
      {:ok, %{status: 200, body: decoded}} -> {:ok, decoded}
      {:ok, %{status: status, body: decoded}} -> {:error, {:http, status, decoded}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp openai_key, do: System.get_env("OPENAI_API_KEY")

  defp base_url do
    Application.get_env(:ellie_ai, __MODULE__, [])
    |> Keyword.get(:base_url, "https://api.openai.com")
  end
end
