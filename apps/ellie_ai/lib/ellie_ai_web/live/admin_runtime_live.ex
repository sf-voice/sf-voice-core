defmodule EllieAiWeb.AdminRuntimeLive do
  @moduledoc """
  per-org runtime settings — the call-loop knobs (vad_silence_ms, voice
  overrides, model overrides, etc). lived briefly at `/admin` while admin
  was a single page; moved here once the hub split landed.

  surfaces every row in `EllieAi.Settings` for the active org, grouped by
  key prefix (vad_*, voice_*, model_*, etc) so related knobs cluster.
  values flow into the call session via the 30s TTL read-through cache.
  """

  use EllieAiWeb, :live_view

  alias EllieAi.Settings

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Runtime")
     |> assign(:active_nav, :admin)
     |> load_settings()}
  end

  defp load_settings(socket) do
    case socket.assigns[:nav_org] do
      nil ->
        assign(socket, :settings_groups, [])

      org ->
        assign(socket, :settings_groups, group_settings(Settings.list(org.id)))
    end
  end

  defp group_settings(settings) do
    sections = %{
      "vad" => "Voice activity detection",
      "voice" => "Voice",
      "model" => "Model",
      "latency" => "Latency",
      "stt" => "Speech-to-text",
      "tts" => "Text-to-speech"
    }

    settings
    |> Enum.group_by(fn s ->
      prefix = s.key |> String.split("_") |> List.first()
      Map.get(sections, prefix, "Other")
    end)
    |> Enum.sort_by(fn {label, _} -> label end)
  end

  @impl true
  def handle_event("save_setting", %{"key" => key, "value" => value}, socket) do
    org = socket.assigns.nav_org

    case Settings.get(org.id, key) do
      nil ->
        {:noreply, put_flash(socket, :error, "Setting #{key} not found")}

      setting ->
        case Settings.put(org.id, key, value, value_type: setting.value_type) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "Saved #{key}")
             |> load_settings()}

          {:error, _cs} ->
            {:noreply, put_flash(socket, :error, "Couldn't save #{key} — check the value type")}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-5">
      <.page_header title="Runtime">
        <:subtitle>
          Per-org call-loop knobs. Changes apply on the next call (30s cache TTL).
        </:subtitle>
      </.page_header>

      <EllieAiWeb.AdminNav.render current={:runtime} />

      <.empty_state
        :if={is_nil(@nav_org)}
        icon="hero-building-office-2"
        title="No org configured"
      >
        <:description>
          Run <code class="mono">mix run priv/repo/seeds.exs</code> to seed a demo org.
        </:description>
      </.empty_state>

      <.empty_state
        :if={@nav_org && @settings_groups == []}
        icon="hero-adjustments-horizontal"
        title="No runtime settings yet"
      >
        <:description>
          Defaults are baked into the call loop. Settings will appear here as soon as
          something writes a row to <code class="mono">settings</code>.
        </:description>
      </.empty_state>

      <div :if={@nav_org && @settings_groups != []} class="space-y-3">
        <.panel :for={{label, group} <- @settings_groups} elevated>
          <:header>
            <h2 class="text-sm font-semibold text-foreground">{label}</h2>
            <span class="font-mono text-[11px] text-muted-foreground">
              {length(group)} keys
            </span>
          </:header>
          <div class="px-5 py-4 space-y-3">
            <.setting_row :for={s <- group} setting={s} />
          </div>
        </.panel>
      </div>
    </div>
    """
  end

  defp setting_row(assigns) do
    ~H"""
    <div class="grid grid-cols-[1fr_2fr_auto] gap-3 items-start">
      <div>
        <div class="mono font-semibold text-foreground text-[13px]">{@setting.key}</div>
        <div :if={@setting.description} class="text-xs text-muted-foreground mt-0.5">
          {@setting.description}
        </div>
      </div>
      <form phx-submit="save_setting" class="flex flex-col gap-2">
        <input type="hidden" name="key" value={@setting.key} />
        <input
          type="text"
          name="value"
          value={@setting.value}
          class="mono w-full px-2.5 py-1.5 rounded-md border border-input bg-card text-foreground transition-shadow duration-[var(--motion-fast)] focus:outline-none focus:ring-2 focus:ring-ring focus:border-ring"
          aria-label={"value for #{@setting.key}"}
        />
        <button
          type="submit"
          class="self-end px-3 py-1 rounded-md border border-primary bg-primary text-primary-foreground text-xs font-medium transition-colors duration-[var(--motion-fast)] hover:bg-primary-hover"
        >
          save
        </button>
      </form>
      <div class="mono text-xs text-muted-foreground pt-1.5">
        {@setting.value_type}
      </div>
    </div>
    """
  end
end
