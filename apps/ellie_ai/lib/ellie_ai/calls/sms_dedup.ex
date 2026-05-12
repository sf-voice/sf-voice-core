defmodule EllieAi.Calls.SmsDedup do
  @moduledoc """
  short-lived ETS dedup for telnyx sms webhook retries. retries within
  TTL no-op; after TTL a rare duplicate gets through — accepted v1
  tradeoff. owned by a tiny GenServer so the table dies with shutdown
  and a periodic sweep evicts old entries.
  """

  use GenServer

  @table __MODULE__
  @ttl_ms 5 * 60 * 1_000
  @sweep_ms 60 * 1_000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "record `message_id`. :fresh = first sighting (proceed); :duplicate = in cache (drop)."
  @spec see(String.t()) :: :fresh | :duplicate
  def see(message_id) when is_binary(message_id) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, message_id) do
      [_] -> :duplicate
      [] ->
        :ets.insert(@table, {message_id, now})
        :fresh
    end
  end

  @impl true
  def init(_) do
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    schedule_sweep()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    cutoff = System.monotonic_time(:millisecond) - @ttl_ms
    :ets.select_delete(@table, [{{:_, :"$1"}, [{:<, :"$1", cutoff}], [true]}])
    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, @sweep_ms)
end
