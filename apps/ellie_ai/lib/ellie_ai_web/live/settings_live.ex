defmodule EllieAiWeb.SettingsLive do
  @moduledoc """

  """

  use EllieAiWeb, :live_view

  alias EllieAi.{Orgs, Prompts}
  alias EllieAi.Orgs.Org
  alias EllieAi.Prompts.Prompt

  # variables the operator can drop into the prompt body. shape matches
  # what the PromptEditor JS hook expects in data-prompt-vars. add new
  # ones here AND make sure `prompt_context/1` below returns the value.
  @prompt_variables [
    %{label: "Restaurant name", value: "org.name"},
    %{label: "Location", value: "org.location"},
    %{label: "Time zone", value: "org.time_zone"},
    %{label: "Caller info (auto)", value: "customer_intro"},
    %{label: "Caller phone (auto)", value: "customer.phone_number"},
    %{label: "Caller name (auto, blank if unknown)", value: "customer.name"}
  ]

  # sample values used in the live preview so operators see what
  # `{{ customer_intro }}` and `{{ customer.* }}` look like before any
  # real call. the real values come from
  # `AudioBridge.customer_context_for/2` at call time.
  @sample_customer_intro "known caller: Alice Wong. last seen 2026-05-08. notes: prefers a quiet table near the window."
  @sample_customer_phone "+14155550100"
  @sample_customer_name "Alice Wong"

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns[:nav_org]

    {:ok,
     socket
     |> assign(:page_title, "Settings")
     |> assign(:active_nav, :settings)
     |> assign(:org, org)
     |> assign(:prompt_variables, @prompt_variables)
     |> assign_org_form(org)
     |> assign_prompt_state(org)}
  end

  defp assign_prompt_state(socket, nil) do
    socket
    |> assign(:active_prompt, nil)
    |> assign(:prompt_versions, [])
  end

  defp assign_prompt_state(socket, %Org{} = org) do
    socket
    |> assign(:active_prompt, Prompts.active(org.id))
    |> assign(:prompt_versions, Prompts.list_versions(org.id))
  end

  # context handed to liquidjs in the browser for live preview. mirrors
  # what audio_bridge passes to Prompts.render!/2 at call time so the
  # preview matches the model's actual input.
  defp prompt_context(%Org{} = org) do
    %{
      "org" => %{
        "name" => org.name,
        "location" => org.location,
        "time_zone" => org.time_zone
      },
      "customer" => %{
        "phone_number" => @sample_customer_phone,
        "name" => @sample_customer_name,
        "known" => true
      },
      "customer_intro" => @sample_customer_intro
    }
  end

  defp assign_org_form(socket, nil), do: assign(socket, :org_form, nil)

  defp assign_org_form(socket, %Org{} = org) do
    assign(socket, :org_form, to_form(Orgs.admin_changeset(org)))
  end

  @impl true
  def handle_event("validate_org", %{"org" => attrs}, socket) do
    changeset =
      socket.assigns.org
      |> Orgs.admin_changeset(attrs)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :org_form, to_form(changeset))}
  end

  def handle_event("save_org", %{"org" => attrs}, socket) do
    case Orgs.update_admin(socket.assigns.org, attrs) do
      {:ok, org} ->
        {:noreply,
         socket
         |> assign(:org, org)
         |> assign_org_form(org)
         |> put_flash(:info, "Org saved")}

      {:error, changeset} ->
        changeset = Map.put(changeset, :action, :update)

        {:noreply,
         socket
         |> assign(:org_form, to_form(changeset))
         |> put_flash(:error, "Couldn't save org — check the fields below")}
    end
  end

  # save the textarea content as a NEW prompt version. save_new_version
  # bumps the version number and flips active to this row in one txn,
  # so the next call picks it up immediately. empty bodies are rejected
  # by the Prompt changeset.
  def handle_event("save_prompt", %{"body" => body}, socket) do
    case Prompts.save_new_version(socket.assigns.org.id, %{
           name: "edited via settings",
           body: body
         }) do
      {:ok, _prompt} ->
        {:noreply,
         socket
         |> assign_prompt_state(socket.assigns.org)
         |> put_flash(:info, "Personality saved — Ellie will use it on the next call.")}

      {:error, changeset} ->
        msg =
          changeset.errors
          |> Enum.map(fn {field, {detail, _}} -> "#{field} #{detail}" end)
          |> Enum.join("; ")

        {:noreply, put_flash(socket, :error, "Couldn't save: #{msg}")}
    end
  end

  # restore an earlier version by flipping it back to active. doesn't
  # create a new row — preserves history as a single linear timeline.
  def handle_event("restore_prompt", %{"id" => id}, socket) do
    case Prompts.activate(socket.assigns.org.id, id) do
      {:ok, _prompt} ->
        {:noreply,
         socket
         |> assign_prompt_state(socket.assigns.org)
         |> put_flash(:info, "Earlier version restored.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Couldn't restore that version.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.empty_state
      :if={is_nil(@org)}
      icon="hero-building-office-2"
      title="No org configured"
    >
      <:description>
        Run <code class="mono">mix run priv/repo/seeds.exs</code>.
      </:description>
    </.empty_state>

    <div :if={@org} class="space-y-5">
      <.page_header title="Settings">
        <:subtitle>
          {@org.name} · <span class="mono">{@org.slug}</span>
        </:subtitle>
      </.page_header>

      <.tabs id="settings-tabs" default="org" class="w-full">
        <.tabs_list class="bg-secondary">
          <.tabs_trigger value="org">Organization</.tabs_trigger>
          <.tabs_trigger value="integrations">Phone &amp; integrations</.tabs_trigger>
          <.tabs_trigger value="personality">Personality</.tabs_trigger>
        </.tabs_list>

        <.tabs_content value="org">
          <section class="rounded-md border border-border bg-card p-5 mt-2">
            <h2 class="text-sm font-semibold text-foreground mb-1">Identity</h2>
            <p class="text-xs text-muted-foreground mb-4">
              What this org is called and where it lives. Time zone drives every
              human-facing date and time.
            </p>

            <.form
              for={@org_form}
              id="org-identity-form"
              phx-submit="save_org"
              phx-change="validate_org"
              class="space-y-3"
            >
              <.org_field form={@org_form} field={:name} label="Name" />
              <.org_field form={@org_form} field={:location} label="Location" />
              <.org_field
                form={@org_form}
                field={:time_zone}
                label="Time zone"
                hint="IANA name, e.g. America/Los_Angeles"
              />
              <.save_button label="Save organization" />
            </.form>
          </section>
        </.tabs_content>

        <.tabs_content value="integrations">
          <section class="rounded-md border border-border bg-card p-5 mt-2">
            <h2 class="text-sm font-semibold text-foreground mb-1">Phone &amp; integrations</h2>
            <p class="text-xs text-muted-foreground mb-4">
              The Telnyx number that maps inbound calls to this org, and the
              Resto deployment we read availability + customers from.
            </p>

            <.form
              for={@org_form}
              id="org-integrations-form"
              phx-submit="save_org"
              phx-change="validate_org"
              class="space-y-3"
            >
              <.org_field
                form={@org_form}
                field={:telnyx_phone_number}
                label="Telnyx phone number"
                hint="E.164 (with country code). e.g. +18774980043"
              />
              <.org_field
                form={@org_form}
                field={:resto_base_url}
                label="Resto base URL"
                hint="e.g. https://resto-demo.sf-voice.sh"
              />
              <.org_field
                form={@org_form}
                field={:resto_org_slug}
                label="Resto org slug"
                hint="lowercase, hyphens. e.g. the-seasons"
              />
              <.save_button label="Save integrations" />
            </.form>
          </section>
        </.tabs_content>

        <.tabs_content value="personality">
          <.personality_panel
            org={@org}
            active_prompt={@active_prompt}
            versions={@prompt_versions}
            variables={@prompt_variables}
          />
        </.tabs_content>
      </.tabs>
    </div>
    """
  end

  # the personality editor — textarea + live preview + version history.
  # the wrapper carries the PromptEditor hook + the JSON-encoded
  # variables and context the hook reads in mounted().
  attr :org, :map, required: true
  attr :active_prompt, :any, required: true
  attr :versions, :list, required: true
  attr :variables, :list, required: true

  defp personality_panel(assigns) do
    ~H"""
    <section class="rounded-md border border-border bg-card p-5 mt-2 space-y-5">
      <header>
        <h2 class="text-sm font-semibold text-foreground mb-1">Personality</h2>
        <p class="text-xs text-muted-foreground">
          What Ellie says when she answers the phone. Type
          <code class="mono">&#123;&#123;</code>
          to insert a value from your restaurant (name, location, time zone).
          The preview below updates as you type.
        </p>
      </header>

      <div
        id="prompt-editor"
        phx-hook="PromptEditor"
        data-prompt-vars={Jason.encode!(@variables)}
        data-prompt-context={Jason.encode!(prompt_context(@org))}
        phx-update="ignore"
        class="relative"
      >
        <form id="prompt-form" phx-submit="save_prompt" class="space-y-3">
          <label for="prompt-body" class="block text-[13px] font-semibold text-foreground">
            Prompt body
          </label>
          <textarea
            id="prompt-body"
            name="body"
            rows="14"
            spellcheck="false"
            class="mono w-full px-3 py-2 rounded-md border border-input bg-card text-foreground text-sm focus:outline-none focus:ring-2 focus:ring-ring focus:border-ring resize-y"
          ><%= prompt_body(@active_prompt) %></textarea>

          <div class="flex items-center justify-between gap-3">
            <p class="text-xs text-muted-foreground">
              Saving creates a new version. Earlier versions are restorable below.
            </p>
            <button
              type="submit"
              class="px-4 py-2 rounded-md border border-primary bg-primary text-primary-foreground text-sm font-medium hover:bg-primary-hover"
            >
              Save personality
            </button>
          </div>
        </form>

        <div class="mt-4">
          <div class="text-[10px] uppercase tracking-[0.12em] font-semibold text-muted-foreground mb-1">
            Preview
          </div>
          <pre
            data-prompt-preview
            data-state="ok"
            class="mono whitespace-pre-wrap break-words text-xs leading-relaxed px-3 py-3 rounded-md bg-secondary text-foreground border border-border data-[state=error]:border-destructive data-[state=error]:text-destructive"
          ></pre>
        </div>
      </div>

      <.prompt_history versions={@versions} active_prompt={@active_prompt} />
    </section>
    """
  end

  attr :versions, :list, required: true
  attr :active_prompt, :any, required: true

  defp prompt_history(assigns) do
    ~H"""
    <details :if={@versions != []} class="border-t border-border pt-4">
      <summary class="text-sm font-semibold text-foreground cursor-pointer select-none">
        Earlier versions ({length(@versions)})
      </summary>
      <ul class="mt-3 space-y-2">
        <li
          :for={version <- @versions}
          class="flex items-start justify-between gap-3 rounded-md border border-border p-3 bg-card"
        >
          <div class="min-w-0 flex-1">
            <div class="flex items-center gap-2 mb-1">
              <span class="text-xs font-semibold text-foreground">v{version.version}</span>
              <span
                :if={active?(version, @active_prompt)}
                class="text-[10px] uppercase tracking-wider font-semibold text-success"
              >
                active
              </span>
              <span class="text-xs text-muted-foreground">
                <.datetime at={version.inserted_at} format={:short} />
              </span>
            </div>
            <p class="text-xs text-muted-foreground line-clamp-2">{snippet(version.body)}</p>
          </div>
          <button
            :if={not active?(version, @active_prompt)}
            type="button"
            phx-click="restore_prompt"
            phx-value-id={version.id}
            class="shrink-0 text-xs font-medium text-primary hover:text-primary-hover"
            aria-label={"Restore version " <> to_string(version.version)}
          >
            Restore
          </button>
        </li>
      </ul>
    </details>
    """
  end

  defp prompt_body(nil), do: ""
  defp prompt_body(%Prompt{body: body}), do: body

  defp active?(%Prompt{id: a}, %Prompt{id: a}), do: true
  defp active?(_, _), do: false

  defp snippet(nil), do: ""
  defp snippet(body) when is_binary(body) do
    body
    |> String.replace(~r/\s+/, " ")
    |> String.slice(0, 140)
    |> Kernel.<>(if String.length(body) > 140, do: "…", else: "")
  end


  defp save_button(assigns) do
    ~H"""
    <div class="pt-1">
      <button
        type="submit"
        class="px-4 py-2 rounded-md border border-primary bg-primary text-primary-foreground text-sm font-medium hover:bg-primary-hover"
      >
        {@label}
      </button>
    </div>
    """
  end

  defp format_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {k, v}, acc ->
      String.replace(acc, "%{#{k}}", to_string(v))
    end)
  end

  # one input row for the Org form. surfaces inline error text in red
  # under the field when the changeset rejects the value.
  defp org_field(assigns) do
    assigns = assign_new(assigns, :hint, fn -> nil end)

    ~H"""
    <div>
      <label for={@form[@field].id} class="block text-[13px] font-semibold text-foreground mb-1">
        {@label}
      </label>
      <input
        type="text"
        id={@form[@field].id}
        name={@form[@field].name}
        value={Phoenix.HTML.Form.normalize_value("text", @form[@field].value)}
        class="mono w-full px-3 py-2 rounded-md border border-input bg-card text-foreground text-sm focus:outline-none focus:ring-2 focus:ring-ring focus:border-ring"
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
end
