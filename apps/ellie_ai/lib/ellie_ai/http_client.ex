defmodule EllieAi.HttpClient do
  @moduledoc """
  shared request option lookup for outbound Req clients.
  """

  @spec request_options(module(), keyword()) :: keyword()
  def request_options(client_module, opts) when is_atom(client_module) and is_list(opts) do
    Keyword.merge(opts, configured_options(client_module))
  end

  defp configured_options(client_module) do
    Application.get_env(:ellie_ai, client_module, [])
    |> Keyword.get(:req_options, [])
  end
end
