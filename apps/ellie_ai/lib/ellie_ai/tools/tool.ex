defmodule EllieAi.Tools.Tool do
  @moduledoc "behaviour every tool implements for the realtime layer."

  @callback name() :: String.t()
  @callback description() :: String.t()
  @callback parameters_schema() :: map()
  @callback execute(args :: map(), context :: map()) ::
              {:ok, term()} | {:error, term()}

  @doc "shape a tool module into the OpenAI Realtime JSON definition."
  def to_openai(module) when is_atom(module) do
    %{
      type: "function",
      name: module.name(),
      description: module.description(),
      parameters: module.parameters_schema()
    }
  end

  @doc "normalise an error reason into a string for the model."
  @spec format_reason(term()) :: String.t()
  def format_reason(reason) when is_binary(reason), do: reason
  def format_reason(reason), do: inspect(reason)
end
