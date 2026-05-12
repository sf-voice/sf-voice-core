defmodule EllieAi.Drain do
  @key {__MODULE__, :draining}

  @doc "is the container currently draining?"
  @spec draining?() :: boolean()
  def draining?, do: :persistent_term.get(@key, false)

  @doc "flip the drain flag on. idempotent."
  @spec drain!() :: :ok
  def drain!, do: :persistent_term.put(@key, true)

  @doc "for tests only — clear the flag."
  @spec reset!() :: :ok
  def reset! do
    _ = :persistent_term.erase(@key)
    :ok
  end
end
