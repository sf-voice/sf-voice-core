defmodule EllieAi.Prompts do
  @moduledoc """
  per-org system-prompt management. append-only versioning: every save
  creates a new row; the `active` flag points at the version that
  renders into the realtime session at call start. flipping the flag
  is the rollback mechanism.
  """

  import Ecto.Query

  alias EllieAi.{Calls, Customers, RestoClient, Utils}
  alias EllieAi.Calls.{Call, Memory}
  alias EllieAi.Customers.CustomerSummary
  alias EllieAi.Orgs.Org
  alias EllieAi.Prompts.{Defaults, Prompt}
  alias EllieAi.Repo

  require Logger

  @doc "list all versions for an org, newest first."
  def list_versions(org_id) when is_binary(org_id) do
    from(p in Prompt, where: p.org_id == ^org_id, order_by: [desc: p.version])
    |> Repo.all()
  end

  @doc "the currently active prompt for an org, or nil if none."
  def active(org_id) when is_binary(org_id) do
    from(p in Prompt, where: p.org_id == ^org_id and p.active == true, limit: 1)
    |> Repo.one()
  end

  @doc "fetch a specific version by id within an org."
  def get(org_id, id) when is_binary(org_id) and is_binary(id) do
    from(p in Prompt, where: p.org_id == ^org_id and p.id == ^id) |> Repo.one()
  end

  @doc """
  append a new version. computes `version` as `max(existing) + 1` and
  flips it to active in one transaction (deactivating any previously
  active row).
  """
  def save_new_version(org_id, attrs) when is_binary(org_id) do
    Repo.transaction(fn ->
      next =
        Repo.one(
          from p in Prompt,
            where: p.org_id == ^org_id,
            select: coalesce(max(p.version), 0)
        ) + 1

      attrs =
        attrs
        |> Utils.stringify_keys()
        |> Map.merge(%{
          "org_id" => org_id,
          "version" => next,
          "active" => true
        })

      from(p in Prompt, where: p.org_id == ^org_id, update: [set: [active: false]])
      |> Repo.update_all([])

      changeset = Prompt.changeset(%Prompt{}, attrs)

      case Repo.insert(changeset) do
        {:ok, prompt} -> prompt
        {:error, cs} -> Repo.rollback(cs)
      end
    end)
  end

  @doc """
  flip an existing version to active (and deactivate the others). used
  for rollback to a known-good prompt.
  """
  def activate(org_id, prompt_id) when is_binary(org_id) and is_binary(prompt_id) do
    Repo.transaction(fn ->
      case get(org_id, prompt_id) do
        nil ->
          Repo.rollback(:not_found)

        prompt ->
          from(p in Prompt, where: p.org_id == ^org_id, update: [set: [active: false]])
          |> Repo.update_all([])

          {:ok, activated} =
            prompt |> Prompt.changeset(%{"active" => true}) |> Repo.update()

          activated
      end
    end)
  end

  @doc """
  render the active prompt body for an org with the supplied assigns.
  raises if no active prompt exists. callers who can't tolerate a
  missing prompt (settings UI, tests) use this. the realtime stack
  should prefer `render/2` (no bang), which falls back to
  `Defaults.fallback/0` instead of crashing the session.

  template syntax is Liquid-style `{{ org.name }}` — same as the
  liquidjs preview in the settings UI, so what an operator sees while
  editing is what the model gets at call time. unknown variables
  render as empty string (matches liquidjs behavior).
  """
  def render!(org_id, assigns) when is_binary(org_id) and is_list(assigns) do
    case active(org_id) do
      nil ->
        raise "no active prompt for org #{org_id}"

      %Prompt{body: body} ->
        render_template(body, assigns)
    end
  end

  @doc """
  render an arbitrary prompt body with assigns. used by the settings
  preview path so operators can see Liquid output without saving.
  """
  def render_template(body, assigns) when is_binary(body) do
    context = normalize_assigns(assigns)

    Regex.replace(~r/\{\{\s*([\w.]+)\s*\}\}/, body, fn _full, path ->
      lookup(context, path) || ""
    end)
  end

  defp normalize_assigns(assigns) when is_list(assigns), do: Map.new(assigns)
  defp normalize_assigns(assigns) when is_map(assigns), do: assigns

  defp lookup(context, path) do
    path
    |> String.split(".")
    |> Enum.reduce(context, fn key, acc ->
      cond do
        is_nil(acc) -> nil
        is_map(acc) or is_list(acc) -> get_field(acc, key)
        true -> nil
      end
    end)
    |> case do
      nil -> nil
      value when is_binary(value) -> value
      value -> to_string(value)
    end
  end

  # both atom-keyed structs/maps and string-keyed maps work — operators
  # can use `{{ org.name }}` whether we hand in a struct or a plain map.
  defp get_field(list, key) when is_list(list) do
    atom_key =
      try do
        String.to_existing_atom(key)
      rescue
        ArgumentError -> nil
      end

    atom_key && Keyword.get(list, atom_key)
  end

  defp get_field(map, key) when is_map(map) do
    atom_key =
      try do
        String.to_existing_atom(key)
      rescue
        ArgumentError -> nil
      end

    cond do
      atom_key && Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      Map.has_key?(map, key) -> Map.get(map, key)
      true -> nil
    end
  end

  @doc """
  render the active prompt body, falling back to `Defaults.fallback/0`
  when no active prompt exists for the org OR when EEx rendering raises
  (malformed template, missing assign, etc.).

  used by the realtime stack at session start so a freshly-seeded org
  without a prompt — or a prompt with a typo — doesn't take down the
  call. operators see broken prompts in the settings UI via `render!/2`
  instead.
  """
  def render(org_id, assigns) when is_binary(org_id) and is_list(assigns) do
    render!(org_id, assigns)
  rescue
    _ -> Defaults.fallback()
  end

  # ── orchestration: fetch context → write to memory → compose prompt ──
  #
  # base_prompt = operator-editable, rendered with `{{ org.* }}` /
  # `{{ customer.* }}`. context block = future reservations + last 3
  # call summaries + rolling transcript. operators never see the context
  # block; the realtime model gets `base + context`.

  @history_limit 3
  @reservation_window_days 30

  @doc """
  fetch context for `ccid`, persist into Memory, render the active prompt
  plus the context block, and stash the final string in
  `Memory.rendered_prompt/1` for audio_bridge to read.
  """
  @spec bootstrap_and_render!(Org.t(), String.t()) :: :ok
  def bootstrap_and_render!(%Org{} = org, ccid) when is_binary(ccid) do
    ctx = load_context(org, ccid)
    Memory.put_call_context(ccid, ctx)
    write_rendered_prompt(org, ccid, ctx)
    :ok
  end

  @doc """
  re-render from Memory's current state. used at the 13-min session
  refresh so the rolling transcript flows into the new instructions.
  """
  @spec re_render!(String.t()) :: :ok
  def re_render!(ccid) when is_binary(ccid) do
    case Memory.org() do
      %Org{} = org ->
        ctx = %{
          customer: Memory.customer(ccid),
          customer_intro: Memory.customer_intro(ccid),
          call_history: Memory.call_history(ccid),
          reservations: Memory.reservations(ccid),
          transcript: Memory.transcript(ccid)
        }

        write_rendered_prompt(org, ccid, ctx)

      _ ->
        :ok
    end
  end

  defp write_rendered_prompt(%Org{id: org_id} = org, ccid, ctx) do
    base =
      try do
        render!(org_id,
          org: org,
          customer: ctx.customer || %{known: false},
          customer_intro: ctx.customer_intro || ""
        )
      rescue
        _ -> Defaults.fallback()
      end

      context_block = render_context_block(ctx)
      final = base <> "\n\n" <> context_block

    Memory.put_call_context(ccid, %{rendered_prompt: final})
  end

  defp load_context(%Org{} = org, ccid) do
    from = caller_phone(ccid)
    customer_summary = if from, do: lookup_customer(org, from), else: nil

    %{
      customer: build_customer_map(customer_summary, from),
      customer_intro: format_customer_intro(customer_summary),
      call_history: load_call_history(customer_summary),
      reservations: load_reservations(org, customer_summary)
    }
  end

  defp caller_phone(ccid) do
    case Calls.get_by_ccid(ccid) do
      %{from_phone: phone} when is_binary(phone) -> phone
      _ -> nil
    end
  end

  defp lookup_customer(org, phone) do
    case Customers.lookup_by_phone(org, phone) do
      {:ok, %CustomerSummary{} = c} -> c
      _ -> nil
    end
  end

  defp build_customer_map(nil, phone),
    do: %{phone_number: phone, name: nil, known: false}

  defp build_customer_map(%CustomerSummary{first_name: nil} = c, phone),
    do: %{phone_number: c.phone_e164 || phone, name: nil, known: false}

  defp build_customer_map(%CustomerSummary{} = c, phone),
    do: %{
      phone_number: c.phone_e164 || phone,
      name: CustomerSummary.display_name(c),
      known: true
    }

  defp format_customer_intro(%CustomerSummary{first_name: fname} = c) when not is_nil(fname) do
    name = CustomerSummary.display_name(c)
    parts = ["known caller: #{name}"]

    parts =
      case c.last_seen_at do
        %DateTime{} = dt -> parts ++ ["last seen #{Calendar.strftime(dt, "%Y-%m-%d")}"]
        _ -> parts
      end

    parts =
      case c.notes do
        notes when is_binary(notes) and notes != "" -> parts ++ ["notes: #{notes}"]
        _ -> parts
      end

    Enum.join(parts, ". ") <> "."
  end

  defp format_customer_intro(_),
    do: "first-time caller — ask for their name."

  defp load_call_history(nil), do: []

  defp load_call_history(%CustomerSummary{id: customer_id}) do
    customer_id
    |> Calls.list_for_customer()
    |> Enum.reject(&is_nil(&1.summary))
    |> Enum.take(@history_limit)
    |> Enum.map(fn %Call{started_at: at, summary: summary} ->
      {format_dt(at), summary}
    end)
  end

  defp load_reservations(_org, nil), do: []

  # `customer_summary.id` is resto's id post-reconciliation. on a brand-new
  # caller the reconcile Task may not have landed yet — the 404 path
  # gracefully returns [].
  defp load_reservations(%Org{} = org, %CustomerSummary{id: customer_id}) do
    case RestoClient.list_customer_reservations(org, customer_id) do
      {:ok, list} when is_list(list) ->
        cutoff = DateTime.utc_now() |> DateTime.add(@reservation_window_days, :day)
        now = DateTime.utc_now()

        list
        |> Enum.map(&normalize_reservation/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.filter(fn r ->
          case r.starts_at_dt do
            %DateTime{} = dt -> DateTime.compare(dt, now) != :lt and DateTime.compare(dt, cutoff) != :gt
            _ -> false
          end
        end)
        |> Enum.sort_by(& &1.starts_at)

      _ ->
        []
    end
  end

  defp normalize_reservation(%{"id" => id, "starts_at" => starts_at, "party_size" => size}) do
    case DateTime.from_iso8601(starts_at) do
      {:ok, dt, _} -> %{id: id, starts_at: starts_at, starts_at_dt: dt, party_size: size}
      _ -> nil
    end
  end

  defp normalize_reservation(_), do: nil

  defp format_dt(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  defp format_dt(_), do: ""

  defp render_context_block(ctx) do
    [
      "## Caller",
      ctx[:customer_intro] || "",
      "",
      "## Upcoming reservations",
      render_reservations(ctx[:reservations] || []),
      "",
      "## Recent calls",
      render_history(ctx[:call_history] || []),
      "",
      "## Conversation so far",
      render_transcript(ctx[:transcript] || [])
    ]
    |> Enum.join("\n")
  end

  defp render_reservations([]), do: "(none)"

  defp render_reservations(list) do
    Enum.map_join(list, "\n", fn r ->
      "- id=#{r.id} starts_at=#{r.starts_at} party_size=#{r.party_size}"
    end)
  end

  defp render_history([]), do: "(none)"

  defp render_history(list) do
    Enum.map_join(list, "\n", fn {at, summary} -> "- #{at} — #{summary}" end)
  end

  defp render_transcript([]), do: "(call just started)"

  defp render_transcript(turns) do
    Enum.map_join(turns, "\n", fn {role, text, _at} -> "#{role}: #{text}" end)
  end
end
