defmodule EllieAi.Llm.Adapter.Anthropic do
  @moduledoc """
  Anthropic Claude adapter for the modular audio backend. v1 STUB.

  the persona system prompts are long (~2 KB each) and identical across
  turns — when wired, this adapter SHOULD set `cache_control` on the
  system block so each subsequent turn hits the cache. that's the main
  reason Claude was picked for the scammer LLM.

  config (when wired): `ANTHROPIC_API_KEY`. default model: claude-sonnet-4-6.
  """

  @behaviour EllieAi.Llm.Adapter

  require Logger

  @impl true
  def available? do
    not is_nil(System.get_env("ANTHROPIC_API_KEY"))
  end

  @impl true
  def generate(_messages, _opts) do
    Logger.warning("Anthropic.generate/2 not implemented (v1 stub)")
    {:error, :not_implemented}
  end

  @impl true
  def stream(_messages, _opts) do
    Logger.warning("Anthropic.stream/2 not implemented (v1 stub)")
    {:error, :not_implemented}
  end
end
