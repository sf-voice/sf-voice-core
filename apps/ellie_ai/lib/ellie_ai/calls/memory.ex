defmodule EllieAi.Calls.Memory do
  @moduledoc """
  in-memory state of a live call and it SHOULD NOT handle I/O with database. Any database fetching should be happening at entity call site `/entity` and when they are passed into Memory module they are stored and dispatched in Memory during a live call.
  two layers:

    1. shared ETS row keyed by ccid — CallTree writes it once; children
       read on init via `bootstrap_from/1`.
    2. process dictionary copy for the hot path — `Memory.org/0` and
       friends are constant-time dict reads.

  `async/1` propagates the dict into a spawned task. don't put
  per-worker private state (file handles, vad rnn, audio counters) here.
  """

  alias EllieAi.{Orgs, Settings}
  alias EllieAi.Calls.{AudioBridge, CallServer, Sentiment, VadGate}
  alias EllieAi.Orgs.Org

  @key :ellie_call_context
  @table :ellie_call_contexts

  # ── shared per-call store ─────────────────────────────────────────────

  defp ensure_table do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, read_concurrency: true])
    end
  end

  @doc "publish a call's context so children can pick it up by ccid. idempotent."
  @spec publish_context(Org.t(), String.t()) :: :ok
  def publish_context(%Org{} = org, ccid) when is_binary(ccid) do
    ensure_table()
    :ets.insert(@table, {ccid, %{org: org, ccid: ccid}})
    :ok
  end

  @doc "remove a call's context on tree shutdown so the table doesn't leak rows."
  @spec drop_context(String.t()) :: :ok
  def drop_context(ccid) when is_binary(ccid) do
    ensure_table()
    :ets.delete(@table, ccid)
    :ok
  end

  # ── per-call dynamic state (writer = Prompts on init, Calls on turns) ─

  @doc "merge per-call context fields (customer, call_history, reservations, rendered_prompt)."
  @spec put_call_context(String.t(), map()) :: :ok
  def put_call_context(ccid, %{} = ctx) when is_binary(ccid) do
    ensure_table()

    case :ets.lookup(@table, ccid) do
      [{^ccid, existing}] -> :ets.insert(@table, {ccid, Map.merge(existing, ctx)})
      [] -> :ets.insert(@table, {ccid, Map.merge(%{ccid: ccid}, ctx)})
    end

    :ok
  end

  @doc "the customer payload (map) for this call, or nil if not loaded yet."
  @spec customer(String.t()) :: map() | nil
  def customer(ccid) when is_binary(ccid), do: ets_field(ccid, :customer)

  @doc "one-line caller-context string baked into the prompt."
  @spec customer_intro(String.t()) :: String.t() | nil
  def customer_intro(ccid) when is_binary(ccid), do: ets_field(ccid, :customer_intro)

  @doc "list of `{starts_at_iso, summary}` for past calls, newest first."
  @spec call_history(String.t()) :: [{String.t(), String.t() | nil}]
  def call_history(ccid) when is_binary(ccid), do: ets_field(ccid, :call_history) || []

  @doc "list of `%{id, starts_at, party_size}` for this caller's reservations."
  @spec reservations(String.t()) :: [map()]
  def reservations(ccid) when is_binary(ccid), do: ets_field(ccid, :reservations) || []

  @doc "rolling transcript for the current call as `{role, text, at}` tuples."
  @spec transcript(String.t()) :: [{String.t(), String.t(), DateTime.t()}]
  def transcript(ccid) when is_binary(ccid), do: ets_field(ccid, :transcript) || []

  @doc "the fully-rendered system prompt openai is using right now."
  @spec rendered_prompt(String.t()) :: String.t() | nil
  def rendered_prompt(ccid) when is_binary(ccid), do: ets_field(ccid, :rendered_prompt)

  @doc "append one turn to the rolling transcript. race-tolerant for single-call-per-restaurant v1."
  @spec append_turn(String.t(), String.t(), String.t(), DateTime.t() | nil) :: :ok
  def append_turn(ccid, role, text, at \\ nil)
      when is_binary(ccid) and is_binary(role) and is_binary(text) do
    ensure_table()
    at = at || DateTime.utc_now() |> DateTime.truncate(:second)

    case :ets.lookup(@table, ccid) do
      [{^ccid, ctx}] ->
        transcript = Map.get(ctx, :transcript, []) ++ [{role, text, at}]
        :ets.insert(@table, {ccid, Map.put(ctx, :transcript, transcript)})

      [] ->
        :ok
    end

    :ok
  end

  @doc "swap one reservation after modify so a chained tool call sees the new shape."
  @spec update_reservation(String.t(), String.t(), map()) :: :ok
  def update_reservation(ccid, id, %{} = attrs) when is_binary(ccid) and is_binary(id) do
    ensure_table()

    case :ets.lookup(@table, ccid) do
      [{^ccid, ctx}] ->
        updated =
          Map.get(ctx, :reservations, [])
          |> Enum.map(fn r -> if r.id == id, do: Map.merge(r, attrs), else: r end)

        :ets.insert(@table, {ccid, Map.put(ctx, :reservations, updated)})

      [] ->
        :ok
    end

    :ok
  end

  @doc "drop one reservation from the per-call list. used after cancel."
  @spec remove_reservation(String.t(), String.t()) :: :ok
  def remove_reservation(ccid, id) when is_binary(ccid) and is_binary(id) do
    ensure_table()

    case :ets.lookup(@table, ccid) do
      [{^ccid, ctx}] ->
        pruned = Map.get(ctx, :reservations, []) |> Enum.reject(&(&1.id == id))
        :ets.insert(@table, {ccid, Map.put(ctx, :reservations, pruned)})

      [] ->
        :ok
    end

    :ok
  end

  defp ets_field(ccid, key) do
    ensure_table()

    case :ets.lookup(@table, ccid) do
      [{^ccid, ctx}] -> Map.get(ctx, key)
      [] -> nil
    end
  end

  @doc "hydrate this process's call context from the ETS row. accessors default when missing."
  @spec bootstrap_from(String.t()) :: :ok
  def bootstrap_from(ccid) when is_binary(ccid) do
    ensure_table()

    case :ets.lookup(@table, ccid) do
      [{^ccid, ctx}] -> Process.put(@key, ctx)
      [] -> :ok
    end

    :ok
  end

  @doc "set the call context for this process. call once per per-call worker on init."
  @spec bootstrap(Org.t(), String.t()) :: :ok
  def bootstrap(%Org{} = org, ccid) when is_binary(ccid) do
    Process.put(@key, %{org: org, ccid: ccid})
    :ok
  end

  @doc "the full Org struct bound to this process, or nil if not bootstrapped."
  @spec org() :: Org.t() | nil
  def org do
    case Process.get(@key) do
      %{org: %Org{} = o} -> o
      _ -> nil
    end
  end

  @doc "shortcut for `Flag.org().id`. nil when not bootstrapped."
  @spec org_id() :: String.t() | nil
  def org_id do
    case org() do
      %Org{id: id} -> id
      _ -> nil
    end
  end

  @doc "the ccid bound to this process. nil when not bootstrapped."
  @spec ccid() :: String.t() | nil
  def ccid do
    case Process.get(@key) do
      %{ccid: c} when is_binary(c) -> c
      _ -> nil
    end
  end

  # ── runtime config accessors ──────────────────────────────────────────
  # resolve via the org's Settings table (ETS-cached). fall back to the
  # compile-time default when unset or when no org is bootstrapped.

  @doc "end-of-turn silence threshold (ms). drives VadGate hysteresis."
  @spec vad_silence_ms() :: pos_integer()
  def vad_silence_ms, do: setting_int("vad_silence_ms", VadGate.default_silence_ms())

  @doc "which vad implementation to use: \"silero\" or \"openai\"."
  @spec vad_mode() :: String.t()
  def vad_mode, do: setting_string("vad_mode", AudioBridge.default_vad_mode())

  @doc "sentiment EMA below this auto-escalates. 0.0–1.0."
  @spec sentiment_threshold() :: float()
  def sentiment_threshold,
    do: setting_float("sentiment_threshold", Sentiment.default_threshold())

  @doc "barge-in confirmation window (ms). below = backchannel (local mute only); above = response.cancel."
  @spec barge_in_cancel_ms() :: pos_integer()
  def barge_in_cancel_ms,
    do: setting_int("barge_in_cancel_ms", CallServer.default_barge_in_cancel_ms())

  @doc "staff phone for escalation. nil if not configured for this org."
  @spec staff_phone() :: String.t() | nil
  def staff_phone do
    case org_id() do
      nil -> System.get_env("STAFF_PHONE_E164")
      id -> Settings.get_value(id, "staff_phone_e164", System.get_env("STAFF_PHONE_E164"))
    end
  end

  # ── task propagation ─────────────────────────────────────────────────

  @doc """
  supervised fire-and-forget that copies this process's call context so
  accessors work in the spawned task.
  """
  @spec async(function()) :: {:ok, pid()} | {:error, term()}
  def async(fun) when is_function(fun, 0) do
    ctx = Process.get(@key)

    Task.Supervisor.start_child(EllieAi.TaskSupervisor, fn ->
      if ctx, do: Process.put(@key, ctx)
      fun.()
    end)
  end

  # ── helpers ───────────────────────────────────────────────────────────

  defp setting(key, default) do
    case org_id() do
      nil -> default
      id -> Settings.get_value(id, key, default)
    end
  end

  defp setting_int(key, default) do
    case setting(key, default) do
      v when is_integer(v) -> v
      v when is_float(v) -> round(v)
      v when is_binary(v) -> parse_int(v, default)
      _ -> default
    end
  end

  defp setting_float(key, default) do
    case setting(key, default) do
      v when is_float(v) -> v
      v when is_integer(v) -> v * 1.0
      v when is_binary(v) -> parse_float(v, default)
      _ -> default
    end
  end

  defp setting_string(key, default) do
    case setting(key, default) do
      v when is_binary(v) -> v
      _ -> default
    end
  end

  defp parse_int(s, default) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> default
    end
  end

  defp parse_float(s, default) do
    case Float.parse(s) do
      {n, _} -> n
      :error -> default
    end
  end

  @doc "resolve an Org by id — for processes that only know call.org_id. nil on miss."
  @spec fetch_org(String.t()) :: Org.t() | nil
  def fetch_org(org_id) when is_binary(org_id), do: Orgs.get(org_id)
  def fetch_org(_), do: nil
end
