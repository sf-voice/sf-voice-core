defmodule EllieAiWeb.AdminSkillsLive do
  @moduledoc """
  list + ad-hoc test the function tools the realtime session can call.

  for each registered module in `EllieAi.Tools.list/0`:
    * show name, description, and the JSON-Schema of its parameters
    * render a form generated from that schema (string → text input,
      number → number input, object/array → JSON textarea)
    * "Run" invokes `module.execute(args, %{org: current_org})` and
      shows the JSON result inline

  intentionally minimal — staff use this to confirm a tool is wired
  before placing a real call. it's not a replacement for full integration
  tests.
  """

  use EllieAiWeb, :live_view

  alias EllieAi.Tools

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Skills")
     |> assign(:active_nav, :admin)
     |> assign(:tools, Tools.list())
     |> assign(:results, %{})
     |> assign(:expanded, MapSet.new())}
  end

  @impl true
  def handle_event("toggle", %{"name" => name}, socket) do
    expanded =
      if MapSet.member?(socket.assigns.expanded, name) do
        MapSet.delete(socket.assigns.expanded, name)
      else
        MapSet.put(socket.assigns.expanded, name)
      end

    {:noreply, assign(socket, :expanded, expanded)}
  end

  def handle_event("run_tool", %{"name" => name} = params, socket) do
    case Tools.find_by_name(name) do
      {:error, :unknown_tool} ->
        {:noreply, put_flash(socket, :error, "Tool #{name} no longer registered")}

      {:ok, module} ->
        org = socket.assigns[:nav_org]
        args = build_args(module, params)
        result = safe_execute(module, args, %{org: org})

        results = Map.put(socket.assigns.results, name, %{args: args, result: result})
        {:noreply, assign(socket, :results, results)}
    end
  end

  # turn a flat form payload into the args map the tool expects, coercing
  # values per the parameters_schema. anything we can't coerce stays as
  # the raw string — the tool's own validation will reject it.
  defp build_args(module, params) do
    schema = module.parameters_schema()
    properties = Map.get(schema, :properties) || Map.get(schema, "properties") || %{}

    Enum.reduce(properties, %{}, fn {key, prop}, acc ->
      key_s = to_string(key)
      raw = params[key_s] || ""
      Map.put(acc, key_s, coerce(raw, prop_type(prop)))
    end)
  end

  defp prop_type(prop) when is_map(prop), do: Map.get(prop, :type) || Map.get(prop, "type")
  defp prop_type(_), do: nil

  defp coerce(raw, "number") do
    case Float.parse(raw) do
      {f, ""} -> f
      _ -> raw
    end
  end

  defp coerce(raw, "integer") do
    case Integer.parse(raw) do
      {i, ""} -> i
      _ -> raw
    end
  end

  defp coerce(raw, "boolean"), do: raw in ["true", "on", "1"]

  defp coerce(raw, t) when t in ["object", "array"] do
    case Jason.decode(raw) do
      {:ok, decoded} -> decoded
      _ -> raw
    end
  end

  defp coerce(raw, _), do: raw

  defp safe_execute(module, args, ctx) do
    try do
      module.execute(args, ctx)
    rescue
      e -> {:error, {:exception, Exception.message(e)}}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-5">
      <.page_header title="Skills">
        <:subtitle>
          The function tools the realtime session can call mid-conversation.
        </:subtitle>
      </.page_header>

      <EllieAiWeb.AdminNav.render current={:skills} />

      <.empty_state
        :if={@tools == []}
        icon="hero-puzzle-piece"
        title="No tools registered"
      >
        <:description>
          Add a module under <code class="mono">lib/ellie_ai/tools/</code>
          implementing the <code class="mono">EllieAi.Tools.Tool</code> behaviour, then
          register it in <code class="mono">config :ellie_ai, EllieAi.Tools</code>.
        </:description>
      </.empty_state>

      <div :if={@tools != []} class="space-y-3">
        <.tool_card
          :for={mod <- @tools}
          mod={mod}
          expanded={MapSet.member?(@expanded, mod.name())}
          result={@results[mod.name()]}
          can_run={!is_nil(@nav_org)}
        />
      </div>

      <p :if={@tools != [] && is_nil(@nav_org)} class="text-xs text-warning">
        Pick an org from the sidebar first. Tools need a context to run against.
      </p>
    </div>
    """
  end

  attr :mod, :atom, required: true
  attr :expanded, :boolean, default: false
  attr :result, :any, default: nil
  attr :can_run, :boolean, default: true

  defp tool_card(assigns) do
    name = assigns.mod.name()
    description = assigns.mod.description()
    schema = assigns.mod.parameters_schema()

    assigns =
      assigns
      |> assign(:name, name)
      |> assign(:description, description)
      |> assign(:schema, schema)
      |> assign(:properties, Map.get(schema, :properties) || Map.get(schema, "properties") || %{})
      |> assign(:required, Map.get(schema, :required) || Map.get(schema, "required") || [])

    ~H"""
    <section class="rounded-md border border-border bg-card overflow-hidden shadow-[var(--shadow-xs)]">
      <button
        type="button"
        phx-click="toggle"
        phx-value-name={@name}
        class="w-full px-5 py-4 flex items-start justify-between gap-4 text-left hover:bg-secondary/40 transition-colors duration-[var(--motion-fast)]"
        aria-expanded={to_string(@expanded)}
      >
        <div class="flex-1 min-w-0">
          <div class="flex items-center gap-2">
            <code class="mono text-[13px] font-semibold text-foreground">{@name}</code>
            <span class="text-[10px] uppercase tracking-[0.1em] font-semibold text-success bg-success-soft px-1.5 py-0.5 rounded">
              registered
            </span>
          </div>
          <p class="mt-1 text-sm text-muted-foreground line-clamp-2">
            {String.trim(@description)}
          </p>
        </div>
        <.icon
          name="hero-chevron-down"
          class={"h-4 w-4 text-muted-foreground shrink-0 transition-transform duration-[var(--motion-base)] " <> if(@expanded, do: "rotate-180", else: "")}
        />
      </button>

      <div :if={@expanded} class="border-t border-border bg-secondary/30">
        <div class="px-5 py-4 grid grid-cols-1 md:grid-cols-2 gap-5">
          <div>
            <.section_label class="mb-2">Parameters</.section_label>
            <form phx-submit="run_tool" class="space-y-2.5">
              <input type="hidden" name="name" value={@name} />
              <.param_input
                :for={{key, prop} <- @properties}
                key={to_string(key)}
                prop={prop}
                required={to_string(key) in Enum.map(@required, &to_string/1)}
              />
              <button
                type="submit"
                disabled={!@can_run}
                class="mt-2 inline-flex items-center gap-1.5 px-3 py-1.5 rounded-md border border-primary bg-primary text-primary-foreground text-sm font-medium hover:bg-primary-hover disabled:opacity-50 disabled:cursor-not-allowed transition-colors duration-[var(--motion-fast)]"
              >
                <.icon name="hero-play" class="h-4 w-4" />
                <span>Run</span>
              </button>
            </form>
          </div>

          <div>
            <.section_label class="mb-2">Schema</.section_label>
            <pre class="mono text-[12px] text-foreground bg-card border border-border rounded-md p-3 overflow-x-auto max-h-64"><%= Jason.encode!(@schema, pretty: true) %></pre>
          </div>
        </div>

        <div :if={@result} class="px-5 pb-5">
          <.section_label class="mb-2">Last run</.section_label>
          <pre class={"mono text-[12px] text-foreground rounded-md p-3 overflow-x-auto max-h-64 border " <> result_class(@result.result)}><%= format_result(@result) %></pre>
        </div>
      </div>
    </section>
    """
  end

  attr :key, :string, required: true
  attr :prop, :any, required: true
  attr :required, :boolean, default: false

  defp param_input(assigns) do
    type = prop_type(assigns.prop)

    description =
      case assigns.prop do
        %{description: d} -> d
        %{"description" => d} -> d
        _ -> nil
      end

    assigns =
      assigns
      |> assign(:type, type)
      |> assign(:description, description)

    ~H"""
    <div>
      <label for={"tool-arg-" <> @key} class="block text-[13px] font-semibold text-foreground mb-1">
        {@key}
        <span :if={@required} class="text-destructive">*</span>
        <span class="font-mono font-normal text-[10px] text-muted-foreground ml-1">
          {@type || "string"}
        </span>
      </label>
      <textarea
        :if={@type in ["object", "array"]}
        id={"tool-arg-" <> @key}
        name={@key}
        rows="3"
        class="mono w-full px-3 py-2 rounded-md border border-input bg-card text-foreground text-[13px] focus:outline-none focus:ring-2 focus:ring-ring transition-shadow duration-[var(--motion-fast)]"
        placeholder={if @type == "array", do: "[]", else: "{}"}
      ></textarea>
      <input
        :if={@type not in ["object", "array"]}
        id={"tool-arg-" <> @key}
        name={@key}
        type={input_type(@type)}
        class="mono w-full px-3 py-2 rounded-md border border-input bg-card text-foreground text-[13px] focus:outline-none focus:ring-2 focus:ring-ring transition-shadow duration-[var(--motion-fast)]"
      />
      <p :if={@description} class="text-xs text-muted-foreground mt-1">{@description}</p>
    </div>
    """
  end

  defp input_type("number"), do: "number"
  defp input_type("integer"), do: "number"
  defp input_type("boolean"), do: "checkbox"
  defp input_type(_), do: "text"

  defp result_class({:ok, _}), do: "border-success bg-success-soft/40"
  defp result_class({:error, _}), do: "border-destructive bg-danger-soft/40"
  defp result_class(_), do: "border-border bg-card"

  defp format_result(%{args: args, result: result}) do
    """
    args:
    #{Jason.encode!(args, pretty: true)}

    result:
    #{format_value(result)}
    """
  end

  defp format_value({:ok, v}), do: "ok: " <> Jason.encode!(v, pretty: true)
  defp format_value({:error, e}), do: "error: " <> inspect(e, pretty: true)
  defp format_value(other), do: inspect(other, pretty: true)
end
