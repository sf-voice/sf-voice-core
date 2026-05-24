defmodule EllieAi.Llm.Adapter do
  @moduledoc """
  behaviour for an LLM provider used by the modular audio backend.
  intentionally narrower than `Medium.Chat` — the modular pipeline needs
  streaming tokens, not a single batch response.

  v1 ships one impl: `EllieAi.Llm.Adapter.Anthropic` (stub).
  """

  @type message :: %{required(:role) => String.t(), required(:content) => String.t()}
  @type opts :: [
          {:model, String.t()}
          | {:temperature, float()}
          | {:max_tokens, pos_integer()}
          | {:system, String.t()}
        ]

  @callback available?() :: boolean()

  @doc "generate a complete response (non-streaming). returns the assistant text."
  @callback generate([message()], opts()) :: {:ok, String.t()} | {:error, term()}

  @doc """
  stream tokens for a response. returns a `Stream.t()` of chunk
  binaries. impls SHOULD enable prompt caching for long system prompts
  when the provider supports it (Anthropic does via cache_control).
  """
  @callback stream([message()], opts()) :: {:ok, Enumerable.t()} | {:error, term()}
end
