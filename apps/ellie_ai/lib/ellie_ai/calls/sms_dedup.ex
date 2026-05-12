defmodule EllieAi.Calls.SmsDedup do
  @moduledoc """
  in-memory dedup cache for inbound telnyx sms webhook ids.

  telnyx retries webhooks on non-2xx. without an external dedup column
  on `transcript_turns`, we keep a short-lived ETS set of message ids
  we've already inserted. a retry that lands within the TTL is a no-op;
  a retry after the TTL gets through and (rarely) lands a duplicate
  row — accepted tradeoff for a single-restaurant v1.

  hooked into the supervision tree as a tiny GenServer that owns the
  ETS table (so the table dies with the supervisor on shutdown rather
  than leaking) and runs a periodic sweep to drop entries older than
  the TTL.
  """

  use GenServer

  @table __MODULE__
  @ttl_ms 5 * 60 * 1_000
  @sweep_ms 60 * 1_000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  record `message_id` as seen. returns `:fresh` if this is the first
  time we've seen it (caller should proceed with the insert) or
  `:duplicate` if it's already in the cache (caller should drop).
  """
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
    # ETS match-delete spec: drop any row whose timestamp is older than cutoff.
    :ets.select_delete(@table, [{{:_, :"$1"}, [{:<, :"$1", cutoff}], [true]}])
    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, @sweep_ms)
end
