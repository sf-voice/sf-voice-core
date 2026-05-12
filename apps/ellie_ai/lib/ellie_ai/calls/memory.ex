defmodule EllieAi.Calls.Memory do
  @moduledoc """
  the in-memory state of a live call. everything a per-call worker
  needs to know without threading args — the org it's serving, the
  ccid it's keyed on, the runtime config the operator dialled in via
  /settings — all lives here and gets read on demand.

  two layers:

    1. **shared ETS row** keyed by ccid. CallTree writes it once at
       boot via `publish/2`; every child process reads it on init via
       `bootstrap_from/1`. drops via `drop/1` when the tree shuts down.

    2. **process dictionary** for the read-hot path. `bootstrap_from/1`
       copies the ETS row into the calling process's dict; subsequent
       `Memory.org/0`, `Memory.vad_silence_ms/0`, etc. are constant-time
       dict reads with no cross-process hop.

  `Memory.async/1` propagates the dict into a spawned task so async
  work (sentiment scoring, tool dispatch) inherits the context.

  what NOT to put here: anything that needs to survive a crash, anything
  shared across calls, the genserver-private state of any one worker
  (file handles, vad rnn state, audio counters — those stay in their
  owning process's struct).
  """

  alias EllieAi.{Orgs, Settings}
  alias EllieAi.Calls.{AudioBridge, CallServer, Sentiment, VadGate}
  alias EllieAi.Orgs.Org

  @key :ellie_call_context
  @table :ellie_call_contexts

  # ── shared per-call store ─────────────────────────────────────────────
  #
  # ETS table keyed by ccid. CallTree writes one row per call at init;
  # every child process reads it on its own init and copies into its
  # process dictionary. when the tree terminates, we delete the row so
  # the table doesn't grow unbounded. one named ETS table for the whole
  # VM, lazily created.

  defp ensure_table do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, read_concurrency: true])
    end
  end

  @doc """
  publish a call's context so child processes can pick it up by ccid.
  called from `CallTree.init/1`. idempotent on repeat with the same ccid.
  """
  @spec publish_context(Org.t(), String.t()) :: :ok
  def publish_context(%Org{} = org, ccid) when is_binary(ccid) do
    ensure_table()
    :ets.insert(@table, {ccid, %{org: org, ccid: ccid}})
    :ok
  end

  @doc """
  remove a call's published context. called when the per-call tree is
  shutting down so the table doesn't leak rows.
  """
  @spec drop_context(String.t()) :: :ok
  def drop_context(ccid) when is_binary(ccid) do
    ensure_table()
    :ets.delete(@table, ccid)
    :ok
  end

  # ── per-call dynamic state (writer = Prompts on init, Calls on turns) ─

  @doc """
  merge per-call context fields (customer, call_history, reservations,
  rendered_prompt) into the shared ETS row. read by audio_bridge,
  sentiment, etc. via the accessors below.
  """
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

  @doc """
  append one turn to the rolling transcript. called from `Calls.append_turn/4`
  so persistence + memory stay in lockstep. race-tolerant for the
  single-call-per-restaurant v1 — concurrent appends are rare.
  """
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

  @doc """
  swap one reservation in the per-call list with a new map. tools call
  this after a successful modify_reservation so a chained tool call
  inside the same turn sees the post-change shape.
  """
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

  @doc """
  hydrate the current process's call context from the shared ETS row.
  child processes call this once on init; after that, `Flag.org/0` and
  friends work without re-touching the table. returns `:ok` even if no
  context was found — accessors gracefully default in that case.
  """
  @spec bootstrap_from(String.t()) :: :ok
  def bootstrap_from(ccid) when is_binary(ccid) do
    ensure_table()

    case :ets.lookup(@table, ccid) do
      [{^ccid, ctx}] -> Process.put(@key, ctx)
      [] -> :ok
    end

    :ok
  end

  @doc """
  set the call context for the current process. call once per per-call
  worker on init (CallServer, AudioBridge, VadGate, Archivist…).
  """
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
  #
  # each one resolves through the org's Settings table (which has its own
  # ETS cache, so these are cheap on the hot path). they fall back to the
  # compile-time default when unset OR when there's no bootstrapped org.

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

  @doc """
  barge-in confirmation window (ms). speech sustained past this fires
  response.cancel at openai. below this is a backchannel — local mute
  handles it; AI's response continues uninterrupted.
  """
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
  like `Task.start/1`, but copies this process's call context into the
  spawned task so `Flag.org/0`, `Flag.vad_silence_ms/0`, etc. work inside
  the task without re-bootstrapping.
  """
  @spec async(function()) :: {:ok, pid()} | {:error, term()}
  def async(fun) when is_function(fun, 0) do
    ctx = Process.get(@key)

    Task.start(fn ->
      if ctx, do: Process.put(@key, ctx)
      fun.()
    end)
  end

  # ── helpers ───────────────────────────────────────────────────────────

  # the org_id might be stale if a workflow caches Flag.bootstrap output
  # past an Org row change. we always re-read by id; the settings cache
  # is the right place to live with TTL'd freshness.
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

  @doc """
  resolve an Org struct by id, suitable for bootstrapping a process that
  only knows the call_id (e.g. Archivist reads call.org_id and needs the
  full org). returns nil on miss.
  """
  @spec fetch_org(String.t()) :: Org.t() | nil
  def fetch_org(org_id) when is_binary(org_id), do: Orgs.get(org_id)
  def fetch_org(_), do: nil
end
