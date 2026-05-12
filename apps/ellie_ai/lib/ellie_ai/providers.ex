defmodule EllieAi.Providers do
  @moduledoc "registry for the active realtime LLM provider."

  # defaults to `EllieAi.Providers.OpenAI` when no config is set.
  def realtime do
    Application.get_env(:ellie_ai, __MODULE__, [])
    |> Keyword.get(:realtime, EllieAi.Providers.OpenAI)
  end
end
