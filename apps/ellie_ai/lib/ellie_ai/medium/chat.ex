defmodule EllieAi.Medium.Chat do
  @moduledoc """
  provider-agnostic chat completions.
  """

  alias EllieAi.Providers.OpenAI

  @doc """
  `messages` is a list of `%{role:, content:}` maps. opts pass through
  to the provider (see `Providers.OpenAI.chat/2` for the supported keys).

  returns `{:ok, content_string}` or `{:error, reason}`.
  """
  @spec generate([map()], keyword()) :: {:ok, String.t()} | {:error, term()}
  def generate(messages, opts \\ []) do
    OpenAI.chat(messages, opts)
  end
end
