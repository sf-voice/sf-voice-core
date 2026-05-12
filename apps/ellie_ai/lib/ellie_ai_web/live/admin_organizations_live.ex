defmodule EllieAiWeb.AdminOrganizationsLive do
  @moduledoc """
  list + create orgs. each org row shows enough at a glance to spot
  whether it's fully wired (has a telnyx number? has resto config?)
  without opening it.

  the "new org" form is intentionally minimal: name, slug, resto base
  URL + slug, group. telnyx number is left blank — provisioning happens
  in Telnyx's portal and the operator pastes the resulting E.164 into
  `/settings → Phone & integrations` once they have it.

  group selection: orgs must belong to a group. we default to the only
  group if exactly one exists; otherwise the operator picks. inline
  group creation is out of scope — manage groups via the seed script or
  iex for now.
  """

  use EllieAiWeb, :live_view

  alias EllieAi.{Groups, Orgs}
  alias EllieAi.Orgs.Org

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Organizations")
     |> assign(:active_nav, :admin)
     |> assign(:modal_open, false)
     |> load_data()
     |> reset_form()}
  end

  defp load_data(socket) do
    socket
    |> assign(:orgs, Orgs.list())
    |> assign(:groups, Groups.list())
  end

  defp reset_form(socket) do
    default_group_id =
      case socket.assigns[:groups] do
        [g] -> g.id
        _ -> nil
      end

    form =
      to_form(
        Orgs.admin_changeset(%Org{group_id: default_group_id}, %{
          time_zone: "America/Los_Angeles"
        })
      )

    assign(socket, :org_form, form)
  end

  @impl true
  def handle_event("open_new", _, socket) do
    {:noreply,
     socket
     |> reset_form()
     |> assign(:modal_open, true)}
  end

  def handle_event("close_new", _, socket) do
    {:noreply, assign(socket, :modal_open, false)}
  end

  def handle_event("validate_new", %{"org" => attrs}, socket) do
    changeset =
      %Org{}
      |> Orgs.admin_changeset(attrs)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :org_form, to_form(changeset))}
  end

  def handle_event("create_new", %{"org" => attrs}, socket) do
    attrs = normalize_attrs(attrs)

    case Orgs.create(attrs) do
      {:ok, org} ->
        {:noreply,
         socket
         |> assign(:modal_open, false)
         |> put_flash(:info, "Created #{org.name}")
         |> load_data()
         |> reset_form()}

      {:error, changeset} ->
        changeset = Map.put(changeset, :action, :insert)

        {:noreply,
         socket
         |> assign(:org_form, to_form(changeset))
         |> put_flash(:error, "Couldn't create — check the fields below")}
    end
  end

  # strip empty telnyx so the changeset normalises it to nil. without this
  # an empty string falls through to libphonenumber parsing and errors.
  defp normalize_attrs(attrs) do
    case attrs["telnyx_phone_number"] do
      "" -> Map.put(attrs, "telnyx_phone_number", nil)
      _ -> attrs
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-5">
      <.page_header title="Organizations">
        <:subtitle>
          One row per restaurant Ellie answers calls for.
        </:subtitle>
        <:actions>
          <button
            type="button"
            phx-click="open_new"
            disabled={@groups == []}
            class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-md border border-primary bg-primary text-primary-foreground text-sm font-medium hover:bg-primary-hover disabled:opacity-50 disabled:cursor-not-allowed transition-colors duration-[var(--motion-fast)]"
            title={if @groups == [], do: "Seed a group first via priv/repo/seeds.exs", else: ""}
          >
            <.icon name="hero-plus" class="h-4 w-4" />
            <span>New organization</span>
          </button>
        </:actions>
      </.page_header>

      <EllieAiWeb.AdminNav.render current={:orgs} />

      <.empty_state
        :if={@orgs == []}
        icon="hero-building-office-2"
        title="No organizations yet"
      >
        <:description>
          Add your first restaurant to start routing calls into Ellie.
        </:description>
      </.empty_state>

      <.panel :if={@orgs != []} elevated>
        <:header>
          <h2 class="text-sm font-semibold text-foreground">
            All organizations <span class="font-mono text-xs text-muted-foreground">{length(@orgs)}</span>
          </h2>
        </:header>
        <ul class="divide-y divide-border">
          <li :for={org <- @orgs} class="px-5 py-3 grid grid-cols-[1.5fr_1.2fr_1fr_auto] gap-4 items-center">
            <div class="min-w-0">
              <div class="font-semibold text-foreground truncate">{org.name}</div>
              <div class="font-mono text-[11px] text-muted-foreground truncate">{org.slug}</div>
            </div>
            <div class="text-sm text-foreground truncate">
              {org.location || "—"}
            </div>
            <div>
              <%= if org.telnyx_phone_number do %>
                <span class="mono text-[13px] text-foreground">{org.telnyx_phone_number}</span>
              <% else %>
                <span class="inline-flex items-center gap-1.5 text-xs text-warning font-medium">
                  <.icon name="hero-exclamation-triangle" class="h-3.5 w-3.5" />
                  No number yet
                </span>
              <% end %>
            </div>
            <div class="text-right">
              <.link
                navigate={~p"/settings"}
                class="text-sm text-primary font-medium"
              >
                edit →
              </.link>
            </div>
          </li>
        </ul>
      </.panel>

      <.new_org_modal
        :if={@modal_open}
        form={@org_form}
        groups={@groups}
      />
    </div>
    """
  end

  attr :form, :any, required: true
  attr :groups, :list, required: true

  defp new_org_modal(assigns) do
    ~H"""
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="new-org-title"
      class="fixed inset-0 z-50 flex items-center justify-center px-4 animate-in fade-in duration-[var(--motion-base)]"
    >
      <div
        class="absolute inset-0 bg-foreground/30 backdrop-blur-sm"
        phx-click="close_new"
        aria-hidden="true"
      >
      </div>

      <div class="relative w-full max-w-md rounded-md border border-border bg-card shadow-[var(--shadow-lg)] animate-in zoom-in-95 fade-in duration-[var(--motion-slow)]">
        <header class="px-5 py-3 border-b border-border flex items-center justify-between">
          <h2 id="new-org-title" class="text-sm font-semibold text-foreground">
            New organization
          </h2>
          <button
            type="button"
            phx-click="close_new"
            class="text-muted-foreground hover:text-foreground transition-colors duration-[var(--motion-fast)]"
            aria-label="Close"
          >
            <.icon name="hero-x-mark" class="h-4 w-4" />
          </button>
        </header>

        <.form
          for={@form}
          phx-submit="create_new"
          phx-change="validate_new"
          class="px-5 py-4 space-y-3"
        >
          <.field form={@form} field={:name} label="Name" placeholder="The Seasons SF" />
          <.field
            form={@form}
            field={:slug}
            label="Slug"
            placeholder="seasons-sf"
            hint="URL-safe identifier. Lowercase, hyphens."
          />
          <.field form={@form} field={:location} label="Location" placeholder="San Francisco, CA" />
          <.field
            form={@form}
            field={:time_zone}
            label="Time zone"
            hint="IANA name, e.g. America/Los_Angeles"
          />

          <.section_label class="pt-3 pb-1">Resto integration</.section_label>
          <.field
            form={@form}
            field={:resto_base_url}
            label="Resto base URL"
            placeholder="https://resto-demo.sf-voice.sh"
          />
          <.field
            form={@form}
            field={:resto_org_slug}
            label="Resto org slug"
            placeholder="the-seasons"
          />

          <.section_label class="pt-3 pb-1">Group</.section_label>
          <div :if={@groups == []} class="text-sm text-warning">
            No groups exist yet. Run the seed script first.
          </div>
          <div :if={@groups != []}>
            <label
              for={@form[:group_id].id}
              class="block text-[13px] font-semibold text-foreground mb-1"
            >
              Belongs to
            </label>
            <select
              id={@form[:group_id].id}
              name={@form[:group_id].name}
              class="w-full px-3 py-2 rounded-md border border-input bg-card text-foreground text-sm focus:outline-none focus:ring-2 focus:ring-ring"
            >
              <option
                :for={g <- @groups}
                value={g.id}
                selected={to_string(@form[:group_id].value) == to_string(g.id)}
              >
                {g.name}
              </option>
            </select>
          </div>

          <p class="text-xs text-muted-foreground pt-2">
            Telnyx number is left empty on create. Add it under
            <span class="mono">Settings → Phone &amp; integrations</span>
            after you provision it.
          </p>

          <div class="flex items-center justify-end gap-2 pt-3 border-t border-border -mx-5 px-5 -mb-4 pb-4">
            <button
              type="button"
              phx-click="close_new"
              class="px-3 py-1.5 rounded-md text-sm font-medium text-foreground hover:bg-secondary transition-colors duration-[var(--motion-fast)]"
            >
              Cancel
            </button>
            <button
              type="submit"
              class="px-4 py-1.5 rounded-md border border-primary bg-primary text-primary-foreground text-sm font-medium hover:bg-primary-hover transition-colors duration-[var(--motion-fast)]"
            >
              Create organization
            </button>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  attr :form, :any, required: true
  attr :field, :atom, required: true
  attr :label, :string, required: true
  attr :hint, :string, default: nil
  attr :placeholder, :string, default: nil

  defp field(assigns) do
    ~H"""
    <div>
      <label
        for={@form[@field].id}
        class="block text-[13px] font-semibold text-foreground mb-1"
      >
        {@label}
      </label>
      <input
        type="text"
        id={@form[@field].id}
        name={@form[@field].name}
        value={Phoenix.HTML.Form.normalize_value("text", @form[@field].value)}
        placeholder={@placeholder}
        class="mono w-full px-3 py-2 rounded-md border border-input bg-card text-foreground text-sm focus:outline-none focus:ring-2 focus:ring-ring focus:border-ring transition-shadow duration-[var(--motion-fast)]"
      />
      <div :if={@hint} class="text-xs text-muted-foreground mt-1">{@hint}</div>
      <div
        :for={err <- @form[@field].errors}
        class="text-[13px] text-destructive font-medium mt-1"
      >
        {format_error(err)}
      </div>
    </div>
    """
  end

  defp format_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {k, v}, acc ->
      String.replace(acc, "%{#{k}}", to_string(v))
    end)
  end
end
