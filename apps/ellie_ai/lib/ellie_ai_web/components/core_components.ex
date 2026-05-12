defmodule EllieAiWeb.CoreComponents do
  @moduledoc """
  shared UI primitives used across the staff console. low-level building
  blocks only — anything page-specific lives in its parent LiveView.

  inventory:
    * `status_pill/1`      colored dot + label for a call's status
    * `datetime/1`         pretty timestamp, mono, tabular figures
    * `phone/1`            phone number rendered in mono
    * `empty_state/1`      icon + title + description for empty surfaces
    * `list_empty/1`       inline "no items here" message inside a panel/table
    * `skeleton/1`         shimmering placeholder for loading states
    * `panel/1`            generic content panel with optional header
    * `page_header/1`      h1 + muted subtitle, consistent across pages
    * `section_label/1`    small uppercase label above a section/group
    * `display_name/1`     "First Last" or "(no name)" from a customer struct
  """

  use Phoenix.Component

  import SaladUI.Icon

  # ── status pill ────────────────────────────────────────────────────────

  @doc "status pill — colored dot label for call status."
  attr :status, :string, required: true
  attr :class, :string, default: ""

  def status_pill(assigns) do
    ~H"""
    <span class={"pill #{@status} #{@class}"}>
      {label_for(@status)}
    </span>
    """
  end

  defp label_for("ringing"), do: "ringing"
  defp label_for("active"), do: "live"
  defp label_for("ended"), do: "ended"
  defp label_for("escalated"), do: "escalated"
  defp label_for(other), do: other

  # ── datetime + phone ───────────────────────────────────────────────────

  @doc "format a UTC datetime as a short local-style string."
  attr :at, :any, required: true
  attr :format, :atom, default: :short

  def datetime(assigns) do
    ~H"""
    <span class="mono">{format_dt(@at, @format)}</span>
    """
  end

  defp format_dt(nil, _), do: "—"

  defp format_dt(%DateTime{} = dt, :short) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  end

  defp format_dt(%DateTime{} = dt, :time) do
    Calendar.strftime(dt, "%H:%M:%S")
  end

  defp format_dt(_, _), do: "—"

  @doc "render a phone number in monospace so digits line up."
  attr :phone, :string, default: nil

  def phone(assigns) do
    ~H"""
    <span class="mono phone">{@phone || "—"}</span>
    """
  end

  # ── empty state ────────────────────────────────────────────────────────

  @doc """
  empty-state placeholder. icon-first, then title, then a one-line
  description. optional action slot for a primary follow-through ("add
  your first X").

  use this for any empty surface that's bigger than a row — table-empty
  cells can stay as inline italic text, but page-level emptiness deserves
  the full pattern.
  """
  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :class, :string, default: ""
  slot :description
  slot :action

  def empty_state(assigns) do
    ~H"""
    <div class={"rounded-lg border border-border bg-card text-center px-6 py-12 " <> @class}>
      <div class="mx-auto mb-3 inline-flex h-10 w-10 items-center justify-center rounded-full bg-secondary text-muted-foreground">
        <.icon name={@icon} class="h-5 w-5" />
      </div>
      <h2 class="text-sm font-semibold text-foreground">{@title}</h2>
      <p :for={d <- @description} class="mt-1 text-sm text-muted-foreground max-w-sm mx-auto">
        {render_slot(d)}
      </p>
      <div :for={a <- @action} class="mt-4">
        {render_slot(a)}
      </div>
    </div>
    """
  end

  # ── inline empty (for use inside a panel/list/table) ───────────────────

  @doc """
  inline "nothing here" message for use inside a `<.panel>`, table, or
  list. smaller and tighter than `<.empty_state>` — no icon, less
  padding, italic muted text.

  reach for `<.list_empty>` when the empty surface is bounded (a panel,
  a row group). reach for `<.empty_state>` when the whole page is empty
  and we want the user to see an icon + call to action.

  the optional `:icon` adds a small heroicon above the text — useful for
  giving a sparse empty list more visual rhythm (langfuse-style).
  """
  attr :class, :string, default: ""
  attr :icon, :string, default: nil
  slot :inner_block, required: true

  def list_empty(assigns) do
    ~H"""
    <div class={"px-5 py-10 text-center text-sm text-muted-foreground italic " <> @class}>
      <.icon
        :if={@icon}
        name={@icon}
        class="h-5 w-5 mx-auto mb-2 not-italic opacity-60"
      />
      {render_slot(@inner_block)}
    </div>
    """
  end

  # ── skeleton ───────────────────────────────────────────────────────────

  @doc """
  shimmering placeholder. used during the brief HTTP→websocket transition
  on LiveView mount, so pages don't flash an empty layout before the
  socket connects and data lands.

  `lines` controls how many stacked rows; `class` lets callers tweak
  width or height of an individual skeleton block.
  """
  attr :lines, :integer, default: 3
  attr :class, :string, default: "h-4"

  def skeleton(assigns) do
    ~H"""
    <div class="space-y-2" aria-hidden="true">
      <div
        :for={_ <- 1..@lines}
        class={"rounded bg-secondary animate-pulse " <> @class}
      >
      </div>
    </div>
    """
  end

  # ── card + headers ─────────────────────────────────────────────────────

  @doc """
  generic content panel. blueprint-tight 4px corners + light shadow.
  named `panel` rather than `card` because SaladUI already exposes a
  `<.card>` with shadcn defaults (12px corners, larger shadow) and the
  two would collide; the rename also leaves SaladUI's card free for any
  shadcn-faithful surface we want to drop in.
  """
  attr :class, :string, default: ""
  attr :elevated, :boolean, default: false
  slot :header
  slot :inner_block, required: true

  def panel(assigns) do
    ~H"""
    <section class={[
      "rounded-lg border border-border bg-card overflow-hidden",
      @elevated && "shadow-[var(--shadow-sm)]",
      @class
    ]}>
      <div :for={h <- @header} class="px-5 py-3 border-b border-border flex items-center justify-between gap-3">
        {render_slot(h)}
      </div>
      <div class={if @header == [], do: "p-5", else: ""}>
        {render_slot(@inner_block)}
      </div>
    </section>
    """
  end

  @doc """
  page header — `<h1>` plus an optional muted subtitle. keeps the type
  scale consistent across every page so the eye lands in the same spot.

  the optional `:icon` renders a leading heroicon next to the title.
  pages that want langfuse-style polished headers should pass one
  (calls = `hero-phone`, customers = `hero-users`, etc.).
  """
  attr :title, :string, required: true
  attr :icon, :string, default: nil
  attr :class, :string, default: ""
  slot :subtitle
  slot :actions

  def page_header(assigns) do
    ~H"""
    <header class={"flex items-end justify-between gap-4 " <> @class}>
      <div>
        <h1 class="text-[22px] leading-tight font-semibold tracking-tight text-foreground flex items-center gap-2.5">
          <.icon
            :if={@icon}
            name={@icon}
            class="h-5 w-5 text-muted-foreground"
          />
          {@title}
        </h1>
        <p :for={s <- @subtitle} class="mt-1 text-sm text-muted-foreground">
          {render_slot(s)}
        </p>
      </div>
      <div :for={a <- @actions} class="flex items-center gap-2 shrink-0">
        {render_slot(a)}
      </div>
    </header>
    """
  end

  @doc """
  small uppercase label that introduces a section or column group.
  matches the sidebar's section headers so the visual rhythm carries
  across the screen.
  """
  attr :class, :string, default: ""
  slot :inner_block, required: true

  def section_label(assigns) do
    ~H"""
    <div class={"text-[10px] uppercase tracking-[0.12em] font-semibold text-muted-foreground " <> @class}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  # ── customer display helpers ───────────────────────────────────────────

  @doc """
  "First Last" from a customer struct, falling back to `"(no name)"` if
  neither name is set. used wherever we render a customer's identity
  (homepage list, calls table, detail page header).

  callers that also need the phone number alongside should render
  `<.phone>` separately — keeping the fallback string short avoids the
  duplicate-phone bug where `display_name` returned "(no name) — phone"
  and the page also rendered `<.phone>` right next to it.
  """
  def display_name(%{first_name: first, last_name: last}) do
    [first, last]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
    |> case do
      "" -> "(no name)"
      name -> name
    end
  end

  # ── editable name ──────────────────────────────────────────────────────

  @doc """
  inline-editable customer name. two modes:

    * read — clickable text (or "+ add name" for unnamed stubs). Enter
      / blur / click outside saves; Escape cancels.
    * edit — autofocused input + form.

  events fire as `phx-click={@edit_event}`, `phx-submit={@save_event}`,
  `phx-blur={@save_event}`, `phx-window-keydown={@cancel_event}` so the
  parent LiveView owns state. the form posts `customer_id` (hidden) +
  `name` (the typed string) — the parent should run
  `EllieAi.Customers.split_name/1` on `name` to derive first/last.

  size controls the type scale: `"default"` for inline list cells,
  `"lg"` for page headers.
  """
  attr :customer, :any, required: true
  attr :editing?, :boolean, required: true
  attr :edit_event, :string, default: "start_edit_name"
  attr :save_event, :string, default: "save_name"
  attr :cancel_event, :string, default: "cancel_edit_name"
  attr :size, :string, default: "default", values: ~w(default lg)

  def editable_name(assigns) do
    full = EllieAi.Customers.full_name(assigns.customer)

    text_class =
      case assigns.size do
        "lg" -> "text-[22px] font-semibold tracking-tight"
        _ -> "text-sm font-semibold"
      end

    input_class =
      case assigns.size do
        "lg" -> "text-[22px] font-semibold tracking-tight"
        _ -> "text-sm font-semibold"
      end

    assigns =
      assigns
      |> assign(:full, full)
      |> assign(:text_class, text_class)
      |> assign(:input_class, input_class)

    ~H"""
    <div :if={!@editing?} class="min-w-0">
      <button
        type="button"
        phx-click={@edit_event}
        phx-value-id={@customer.id}
        class={[
          "text-left truncate max-w-full",
          (@full == "" && "text-muted-foreground italic") ||
            "#{@text_class} text-foreground",
          "hover:text-primary hover:underline decoration-dotted underline-offset-4",
          "transition-colors duration-[var(--motion-fast)]"
        ]}
        title="Click to edit name"
      >
        <%= if @full == "" do %>
          + add name
        <% else %>
          {@full}
        <% end %>
      </button>
    </div>

    <form
      :if={@editing?}
      phx-submit={@save_event}
      phx-window-keydown={@cancel_event}
      phx-key="Escape"
      class="min-w-0"
    >
      <input type="hidden" name="customer_id" value={@customer.id} />
      <input
        type="text"
        name="name"
        value={@full}
        placeholder="First Last"
        autocomplete="off"
        autofocus
        phx-blur={@save_event}
        phx-value-id={@customer.id}
        class={[
          "w-full px-2 py-1 rounded border border-ring bg-card text-foreground",
          "focus:outline-none focus:ring-2 focus:ring-ring",
          @input_class
        ]}
      />
    </form>
    """
  end
end
