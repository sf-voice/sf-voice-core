defmodule RestoBookingAppWeb.FloorPlanLive do
  @moduledoc """
  the landing page for nibble. shows the day's floor plan as a timeline grid
  of tables × 30-min slots. clicking a free slot opens a reserve modal;
  clicking a booked slot opens a manage modal where the owner of the
  reservation (identified by their cancel_token, persisted in localStorage)
  can edit or cancel.

  state lives entirely in this module — the modal flow is driven by the
  `:modal` assign, which is one of:
    * `nil`         — no modal open
    * `:reserve`    — booking form for an empty slot
    * `:saved`      — success screen showing the cancel_token to copy
    * `:manage`     — view / edit / cancel an existing reservation

  cancel tokens are kept in browser localStorage via the `TokenVault` js
  hook, so a user who books from this device can edit and cancel without
  ever pasting a token. someone else can still manage a booking by entering
  the token manually in the manage modal.
  """

  use RestoBookingAppWeb, :live_view

  alias Phoenix.LiveView.JS
  alias RestoBookingApp.{Clock, Reservations, Tables}
  alias RestoBookingApp.Reservations.Reservation

  # display columns: 06:00 through 21:30 in 30-min steps
  @display_start_minutes 6 * 60
  @display_end_minutes 22 * 60

  # ── lifecycle ────────────────────────────────────────────────────────────

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Reservations.subscribe()

    today = Clock.today()

    {:ok,
     socket
     |> assign(:tables, Tables.all())
     |> assign(:slots, build_slots())
     |> assign(:selected_date, today)
     |> assign(:date_input, Date.to_iso8601(today))
     |> assign(:availability, Reservations.availability_for_date(today))
     |> assign(:my_tokens, %{})
     |> assign(:modal, nil)
     |> assign(:reserve_form, nil)
     |> assign(:reserve_context, nil)
     |> assign(:saved_reservation, nil)
     |> assign(:managing, nil)
     |> assign(:manage_form, nil)
     |> assign(:manage_mode, :view)
     |> assign(:manage_token_input, "")
     |> assign(:manage_error, nil)
     |> assign(:page_title, "Floor Plan")}
  end

  # ── token vault ──────────────────────────────────────────────────────────

  @impl true
  def handle_event("vault:loaded", %{"tokens" => tokens}, socket) when is_map(tokens) do
    {:noreply, assign(socket, :my_tokens, tokens)}
  end

  # ── date picker ──────────────────────────────────────────────────────────

  @impl true
  def handle_event("change_date", %{"date" => date_str}, socket) do
    case Date.from_iso8601(date_str) do
      {:ok, date} ->
        {:noreply,
         socket
         |> assign(:selected_date, date)
         |> assign(:date_input, Date.to_iso8601(date))
         |> assign(:availability, Reservations.availability_for_date(date))}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  # ── reserve flow ─────────────────────────────────────────────────────────

  @impl true
  def handle_event("open_reserve", %{"table" => table_id, "minutes" => minutes_str}, socket) do
    minutes = String.to_integer(minutes_str)

    if minutes > Reservation.last_start_hour() * 60 do
      # no booking can start past 20:00 — gently refuse
      {:noreply, put_flash(socket, :error, "Last booking starts at 20:00 (it's a 2-hour slot).")}
    else
      {:ok, starts_at} = slot_datetime(socket.assigns.selected_date, minutes)
      table = Tables.get(table_id)
      default_party = min(2, table.seats)

      changeset =
        %Reservation{}
        |> Reservation.changeset(%{
          "table_id" => table_id,
          "starts_at" => starts_at,
          "party_size" => default_party
        })
        |> Map.put(:action, nil)

      {:noreply,
       socket
       |> assign(:modal, :reserve)
       |> assign(:reserve_context, %{
         table_id: table_id,
         starts_at: starts_at,
         minutes: minutes,
         seats: table.seats
       })
       |> assign(:reserve_form, to_form(changeset, as: "reservation"))}
    end
  end

  @impl true
  def handle_event("validate_reserve", %{"reservation" => params}, socket) do
    ctx = socket.assigns.reserve_context

    changeset =
      %Reservation{}
      |> Reservation.changeset(merge_context(params, ctx))
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :reserve_form, to_form(changeset, as: "reservation"))}
  end

  @impl true
  def handle_event("submit_reserve", %{"reservation" => params}, socket) do
    ctx = socket.assigns.reserve_context

    case Reservations.create(merge_context(params, ctx)) do
      {:ok, reservation} ->
        {:noreply,
         socket
         |> assign(:modal, :saved)
         |> assign(:saved_reservation, reservation)
         |> push_event("vault:save", %{id: reservation.id, token: reservation.cancel_token})
         |> update(:my_tokens, &Map.put(&1, reservation.id, reservation.cancel_token))
         |> assign(:availability, refresh_availability(socket))}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, assign(socket, :reserve_form, to_form(cs, as: "reservation"))}
    end
  end

  @impl true
  def handle_event("dismiss_saved", _params, socket) do
    {:noreply,
     socket
     |> assign(:modal, nil)
     |> assign(:saved_reservation, nil)}
  end

  @impl true
  def handle_event("copy_token", %{"text" => text}, socket) do
    {:noreply,
     socket
     |> push_event("vault:copy", %{text: text})
     |> put_flash(:info, "Cancel token copied to clipboard.")}
  end

  # ── manage flow ──────────────────────────────────────────────────────────

  @impl true
  def handle_event("open_manage", %{"id" => id}, socket) do
    case Reservations.get(id) do
      nil ->
        {:noreply, put_flash(socket, :error, "That reservation no longer exists.")}

      reservation ->
        {:noreply, open_manage_modal(socket, reservation)}
    end
  end

  @impl true
  def handle_event("submit_token", %{"token" => token}, socket) do
    %{managing: reservation} = socket.assigns

    if Plug.Crypto.secure_compare(reservation.cancel_token, token) do
      {:noreply,
       socket
       |> update(:my_tokens, &Map.put(&1, reservation.id, token))
       |> push_event("vault:save", %{id: reservation.id, token: token})
       |> assign(:manage_error, nil)
       |> assign(:manage_mode, :edit)
       |> assign(:manage_form, build_edit_form(reservation))}
    else
      {:noreply, assign(socket, :manage_error, "That token doesn't match this reservation.")}
    end
  end

  @impl true
  def handle_event("validate_edit", %{"reservation" => params}, socket) do
    cs =
      socket.assigns.managing
      |> Reservation.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :manage_form, to_form(cs, as: "reservation"))}
  end

  @impl true
  def handle_event("submit_edit", %{"reservation" => params}, socket) do
    %{managing: reservation, my_tokens: tokens} = socket.assigns
    token = Map.get(tokens, reservation.id)

    case Reservations.update(reservation.id, token, params) do
      {:ok, _updated} ->
        {:noreply,
         socket
         |> assign(:modal, nil)
         |> assign(:managing, nil)
         |> assign(:availability, refresh_availability(socket))
         |> put_flash(:info, "Reservation updated.")}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, assign(socket, :manage_form, to_form(cs, as: "reservation"))}

      {:error, :invalid_token} ->
        {:noreply, assign(socket, :manage_error, "Token rejected — please re-enter.")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "That reservation no longer exists.")}
    end
  end

  @impl true
  def handle_event("ask_delete", _params, socket) do
    {:noreply, assign(socket, :manage_mode, :confirm_delete)}
  end

  @impl true
  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :manage_mode, :edit)}
  end

  @impl true
  def handle_event("delete_reservation", _params, socket) do
    %{managing: reservation, my_tokens: tokens} = socket.assigns
    token = Map.get(tokens, reservation.id)

    case Reservations.delete(reservation.id, token) do
      :ok ->
        {:noreply,
         socket
         |> assign(:modal, nil)
         |> assign(:managing, nil)
         |> update(:my_tokens, &Map.delete(&1, reservation.id))
         |> push_event("vault:remove", %{id: reservation.id})
         |> assign(:availability, refresh_availability(socket))
         |> put_flash(:info, "Reservation cancelled.")}

      {:error, :invalid_token} ->
        {:noreply, assign(socket, :manage_error, "Token rejected — please re-enter.")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "That reservation no longer exists.")}
    end
  end

  @impl true
  def handle_event("close_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:modal, nil)
     |> assign(:reserve_form, nil)
     |> assign(:reserve_context, nil)
     |> assign(:saved_reservation, nil)
     |> assign(:managing, nil)
     |> assign(:manage_form, nil)
     |> assign(:manage_mode, :view)
     |> assign(:manage_token_input, "")
     |> assign(:manage_error, nil)}
  end

  # ── pubsub fanout ────────────────────────────────────────────────────────

  @impl true
  def handle_info({event, _payload}, socket)
      when event in [:reservation_created, :reservation_updated, :reservation_cancelled] do
    {:noreply, assign(socket, :availability, refresh_availability(socket))}
  end

  # ── render ───────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div id="token-vault" phx-hook="TokenVault" class="hidden"></div>

      <section class="mb-8">
        <div class="flex flex-col sm:flex-row sm:items-end sm:justify-between gap-4">
          <div>
            <h1 class="font-display text-5xl text-primary leading-none">welcome to the seasons</h1>
            <p class="mt-2 text-base-content/70 text-sm sm:text-base max-w-xl">
              Thirty seats. Three meals a day. Open every day, 6am to 10pm.
              Pick a free slot to reserve, or click your booking to change it.
            </p>
          </div>
          <form phx-change="change_date" class="flex items-center gap-2 self-start sm:self-end">
            <label for="date" class="text-sm font-semibold">Date</label>
            <input
              type="date"
              id="date"
              name="date"
              value={@date_input}
              class="input input-bordered input-sm rounded-full"
            />
          </form>
        </div>
      </section>

      <section class="mb-10">
        <div class="rounded-3xl bg-base-100/80 backdrop-blur p-3 sm:p-5 shadow-sm border border-base-300">
          <.legend />
          <div class="overflow-x-auto mt-3">
            <table class="w-full text-[10px] sm:text-xs border-separate" style="border-spacing: 4px">
              <thead>
                <tr>
                  <th class="text-left sticky left-0 bg-base-100/80 backdrop-blur z-10 px-2">
                    <span class="opacity-60 font-semibold uppercase tracking-wider text-[10px]">
                      Table
                    </span>
                  </th>
                  <th
                    :for={slot <- @slots}
                    class={[
                      "text-center font-mono font-semibold opacity-70",
                      slot > Reservation.last_start_hour() * 60 && "opacity-30"
                    ]}
                  >
                    {format_slot(slot)}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr :for={table <- @tables}>
                  <th class="text-left sticky left-0 bg-base-100/80 backdrop-blur z-10 px-2 py-1 align-middle whitespace-nowrap">
                    <div class="flex items-center gap-2">
                      <span class="font-mono font-bold text-sm">{table.id}</span>
                      <span class="seat-pip">{table.seats} seats</span>
                    </div>
                    <div class="text-[10px] opacity-50 mt-0.5">{table.shape}</div>
                  </th>
                  <td
                    :for={slot <- @slots}
                    class="p-0 align-middle"
                  >
                    <.slot_cell
                      table={table}
                      minutes={slot}
                      reservation={reservation_at(table.id, slot, @availability, @selected_date)}
                      first_slot?={
                        first_slot_of?(
                          reservation_at(table.id, slot, @availability, @selected_date),
                          slot,
                          @selected_date
                        )
                      }
                      mine?={
                        case reservation_at(table.id, slot, @availability, @selected_date) do
                          nil -> false
                          res -> Map.has_key?(@my_tokens, res.id)
                        end
                      }
                      bookable?={slot <= Reservation.last_start_hour() * 60}
                    />
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </section>

      <.your_bookings_section my_tokens={@my_tokens} availability={@availability} />

      <p class="mt-12 text-center text-xs opacity-50">
        Building something? <.link href="/api" class="underline">See the HTTP API →</.link>
      </p>

      <%= if @modal == :reserve do %>
        <.reserve_modal form={@reserve_form} ctx={@reserve_context} date={@selected_date} />
      <% end %>

      <%= if @modal == :saved do %>
        <.saved_modal reservation={@saved_reservation} />
      <% end %>

      <%= if @modal == :manage do %>
        <.manage_modal
          reservation={@managing}
          mode={@manage_mode}
          form={@manage_form}
          tokens={@my_tokens}
          token_error={@manage_error}
          slots={@slots}
          tables={@tables}
          date={@selected_date}
          max_seats={@tables |> Enum.map(& &1.seats) |> Enum.max()}
        />
      <% end %>
    </Layouts.app>
    """
  end

  # ── components ───────────────────────────────────────────────────────────

  defp legend(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-3 text-xs px-2">
      <div class="flex items-center gap-1.5">
        <span class="inline-block w-4 h-4 rounded-md slot-free border border-base-300"></span>
        <span class="opacity-70">free — click to reserve</span>
      </div>
      <div class="flex items-center gap-1.5">
        <span class="inline-block w-4 h-4 rounded-md slot-taken"></span>
        <span class="opacity-70">booked</span>
      </div>
      <div class="flex items-center gap-1.5">
        <span class="inline-block w-4 h-4 rounded-md slot-taken-mine"></span>
        <span class="opacity-70">yours — click to manage</span>
      </div>
    </div>
    """
  end

  attr :table, :map, required: true
  attr :minutes, :integer, required: true
  attr :reservation, :any, required: true
  attr :first_slot?, :boolean, required: true
  attr :mine?, :boolean, required: true
  attr :bookable?, :boolean, required: true

  defp slot_cell(%{reservation: nil} = assigns) do
    ~H"""
    <button
      type="button"
      phx-click="open_reserve"
      phx-value-table={@table.id}
      phx-value-minutes={@minutes}
      disabled={!@bookable?}
      class={[
        "slot-free w-14 h-9 rounded-lg border border-base-300 text-base-content/30 text-lg leading-none cursor-pointer disabled:cursor-not-allowed disabled:opacity-40",
        !@bookable? && "slot-continuation"
      ]}
      title={
        if(@bookable?,
          do: "Reserve #{@table.id} at #{format_slot(@minutes)}",
          else: "Past last bookable start (20:00)"
        )
      }
    >
      +
    </button>
    """
  end

  defp slot_cell(%{reservation: _res} = assigns) do
    ~H"""
    <button
      type="button"
      phx-click="open_manage"
      phx-value-id={@reservation.id}
      class={[
        "w-14 h-9 rounded-lg cursor-pointer overflow-hidden text-left px-1.5",
        if(@mine?, do: "slot-taken-mine", else: "slot-taken"),
        !@first_slot? && "slot-continuation"
      ]}
      title={"#{@reservation.name} · party of #{@reservation.party_size}#{if @reservation.dietary, do: " · " <> @reservation.dietary, else: ""}"}
    >
      <%= if @first_slot? do %>
        <div class="font-bold text-[10px] truncate leading-tight">
          {@reservation.name} <span class="opacity-70">×{@reservation.party_size}</span>
        </div>
        <div class="text-[9px] truncate opacity-80 leading-tight">
          {@reservation.dietary || ""}
        </div>
      <% end %>
    </button>
    """
  end

  defp your_bookings_section(assigns) do
    assigns =
      assign(
        assigns,
        :mine,
        assigns.availability
        |> Map.values()
        |> List.flatten()
        |> Enum.filter(&Map.has_key?(assigns.my_tokens, &1.id))
        |> Enum.sort_by(& &1.starts_at)
      )

    ~H"""
    <%= if @mine != [] do %>
      <section class="mb-10">
        <h2 class="font-display text-3xl text-primary mb-3">your bookings today</h2>
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
          <button
            :for={res <- @mine}
            type="button"
            phx-click="open_manage"
            phx-value-id={res.id}
            class="text-left rounded-2xl bg-base-100 border border-base-300 p-4 hover:border-secondary hover:shadow-md transition-all cursor-pointer"
          >
            <div class="flex items-center justify-between gap-2">
              <span class="font-bold">{res.name}</span>
              <span class="text-[10px] font-mono opacity-60">{res.table_id}</span>
            </div>
            <div class="mt-1 text-sm opacity-80 font-mono">
              {format_dt(res.starts_at)} → {format_dt(res.ends_at)}
            </div>
            <div class="mt-1 text-xs opacity-70">
              party of {res.party_size}
            </div>
            <div :if={res.dietary} class="mt-0.5 text-xs opacity-70 italic">
              {res.dietary}
            </div>
            <div :if={res.notes} class="mt-0.5 text-xs opacity-70">
              {res.notes}
            </div>
            <div class="mt-2 text-xs text-secondary font-semibold">click to edit or cancel →</div>
          </button>
        </div>
      </section>
    <% end %>
    """
  end

  attr :form, :any, required: true
  attr :ctx, :map, required: true
  attr :date, :any, required: true

  defp reserve_modal(assigns) do
    ~H"""
    <.modal_shell title="Reserve a table">
      <div class="rounded-2xl bg-accent/30 px-4 py-3 mb-4 text-sm">
        <div class="font-bold">Table {@ctx.table_id} · seats up to {@ctx.seats}</div>
        <div class="opacity-80 font-mono">
          {Date.to_iso8601(@date)} · {format_slot(@ctx.minutes)} – {format_slot(@ctx.minutes + 120)}
        </div>
      </div>

      <.form
        for={@form}
        phx-change="validate_reserve"
        phx-submit="submit_reserve"
        class="space-y-2"
      >
        <.input field={@form[:name]} type="text" label="Your name" placeholder="Avery Chen" required />
        <.input
          field={@form[:party_size]}
          type="number"
          label={"How many people? (1–#{@ctx.seats})"}
          min="1"
          max={@ctx.seats}
          required
        />
        <.input
          field={@form[:dietary]}
          type="text"
          label="Dietary requirements (optional)"
          placeholder="vegan, no peanuts, gluten free…"
        />
        <.input
          field={@form[:notes]}
          type="textarea"
          label="notes (optional)"
          placeholder="anything else? what you want to eat, occasion, requests…"
        />

        <div class="flex items-center justify-end gap-2 pt-3">
          <button type="button" phx-click="close_modal" class="btn btn-ghost rounded-full">
            Never mind
          </button>
          <button type="submit" class="btn btn-primary rounded-full">
            Reserve
          </button>
        </div>
      </.form>
    </.modal_shell>
    """
  end

  attr :reservation, :any, required: true

  defp saved_modal(assigns) do
    ~H"""
    <.modal_shell title="Booked!">
      <div class="text-center mb-4">
        <div class="font-display text-4xl text-secondary">yay 🎀</div>
        <p class="text-sm opacity-80 mt-1">
          We saved your spot. Your cancel token is below — we've also stored it
          in this browser, so you can edit or cancel any time without re-typing.
        </p>
      </div>

      <div class="rounded-2xl bg-base-200 p-4 mb-4 space-y-1 text-sm">
        <div>
          <span class="opacity-60">Name:</span> <span class="font-bold">{@reservation.name}</span>
        </div>
        <div>
          <span class="opacity-60">Party:</span>
          <span class="font-bold">
            {@reservation.party_size} {pluralize_people(@reservation.party_size)}
          </span>
        </div>
        <div>
          <span class="opacity-60">Table:</span>
          <span class="font-mono">{@reservation.table_id}</span>
        </div>
        <div>
          <span class="opacity-60">Time:</span>
          <span class="font-mono">
            {format_dt(@reservation.starts_at)} → {format_dt(@reservation.ends_at)}
          </span>
        </div>
        <div :if={@reservation.dietary}>
          <span class="opacity-60">Dietary:</span> <span class="italic">{@reservation.dietary}</span>
        </div>
        <div :if={@reservation.notes}>
          <span class="opacity-60">Notes:</span> {@reservation.notes}
        </div>
      </div>

      <label class="text-xs uppercase tracking-wider opacity-60 font-semibold">Cancel token</label>
      <div class="flex items-center gap-2 mt-1">
        <code class="flex-1 rounded-xl bg-base-300 px-3 py-2 font-mono text-xs break-all">
          {@reservation.cancel_token}
        </code>
        <button
          type="button"
          phx-click="copy_token"
          phx-value-text={@reservation.cancel_token}
          class="btn btn-secondary btn-sm rounded-full"
        >
          Copy
        </button>
      </div>

      <div class="text-right mt-5">
        <button type="button" phx-click="dismiss_saved" class="btn btn-primary rounded-full">
          Done
        </button>
      </div>
    </.modal_shell>
    """
  end

  attr :reservation, :any, required: true
  attr :mode, :atom, required: true
  attr :form, :any, required: true
  attr :tokens, :map, required: true
  attr :token_error, :any, required: true
  attr :slots, :list, required: true
  attr :tables, :list, required: true
  attr :date, :any, required: true
  attr :max_seats, :integer, required: true

  defp manage_modal(assigns) do
    has_token? = Map.has_key?(assigns.tokens, assigns.reservation.id)
    assigns = assign(assigns, :has_token?, has_token?)

    ~H"""
    <.modal_shell title="Reservation">
      <div class="rounded-2xl bg-accent/30 px-4 py-3 mb-4 text-sm space-y-1">
        <div>
          <span class="opacity-60">Name:</span> <span class="font-bold">{@reservation.name}</span>
        </div>
        <div>
          <span class="opacity-60">Party:</span>
          <span class="font-bold">
            {@reservation.party_size} {pluralize_people(@reservation.party_size)}
          </span>
        </div>
        <div>
          <span class="opacity-60">Table:</span>
          <span class="font-mono">{@reservation.table_id}</span>
        </div>
        <div>
          <span class="opacity-60">Time:</span>
          <span class="font-mono">
            {format_dt(@reservation.starts_at)} → {format_dt(@reservation.ends_at)}
          </span>
        </div>
        <div :if={@reservation.dietary}>
          <span class="opacity-60">Dietary:</span>
          <span class="italic">{@reservation.dietary}</span>
        </div>
        <div :if={@reservation.notes}>
          <span class="opacity-60">Notes:</span>
          {@reservation.notes}
        </div>
      </div>

      <%= cond do %>
        <% not @has_token? -> %>
          <p class="text-sm mb-2 opacity-80">
            To edit or cancel this booking, paste the cancel token returned at
            booking time:
          </p>
          <form phx-submit="submit_token" class="flex items-center gap-2">
            <input
              type="text"
              name="token"
              placeholder="cancel token"
              class="input input-bordered rounded-full flex-1 font-mono text-xs"
              required
            />
            <button type="submit" class="btn btn-secondary rounded-full">
              Unlock
            </button>
          </form>
          <p :if={@token_error} class="text-error text-sm mt-2">{@token_error}</p>
        <% @mode == :confirm_delete -> %>
          <div class="rounded-2xl bg-error/15 border border-error/30 p-4 text-sm">
            <p class="font-bold mb-2">Cancel this reservation?</p>
            <p class="opacity-80">This can't be undone — the slot frees up immediately.</p>
            <div class="flex items-center justify-end gap-2 mt-4">
              <button
                type="button"
                phx-click="cancel_delete"
                class="btn btn-ghost btn-sm rounded-full"
              >
                Keep it
              </button>
              <button
                type="button"
                phx-click="delete_reservation"
                class="btn btn-error btn-sm rounded-full"
              >
                Yes, cancel
              </button>
            </div>
          </div>
        <% true -> %>
          <.form
            :let={f}
            for={@form}
            phx-change="validate_edit"
            phx-submit="submit_edit"
            class="space-y-2"
          >
            <.input
              field={f[:name]}
              type="text"
              label="Name"
              required
            />
            <.input
              field={f[:party_size]}
              type="number"
              label={"How many people? (1–#{@max_seats})"}
              min="1"
              max={@max_seats}
              required
            />
            <.input
              field={f[:dietary]}
              type="text"
              label="Dietary requirements"
            />
            <.input
              field={f[:notes]}
              type="textarea"
              label="notes"
            />
            <.input
              field={f[:table_id]}
              type="select"
              label="Table"
              options={for t <- @tables, do: {"#{t.id} (#{t.seats} seats)", t.id}}
            />
            <.input
              field={f[:starts_at]}
              type="select"
              label="Start time"
              options={start_time_options(@date, @slots)}
            />

            <p :if={@token_error} class="text-error text-sm">{@token_error}</p>

            <div class="flex items-center justify-between gap-2 pt-3">
              <button
                type="button"
                phx-click="ask_delete"
                class="btn btn-ghost text-error rounded-full"
              >
                Cancel reservation
              </button>
              <div class="flex items-center gap-2">
                <button type="button" phx-click="close_modal" class="btn btn-ghost rounded-full">
                  Close
                </button>
                <button type="submit" class="btn btn-primary rounded-full">
                  Save changes
                </button>
              </div>
            </div>
          </.form>
      <% end %>
    </.modal_shell>
    """
  end

  attr :title, :string, required: true
  slot :inner_block, required: true

  defp modal_shell(assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-40 flex items-center justify-center p-4"
      phx-window-keydown="close_modal"
      phx-key="escape"
    >
      <div
        class="absolute inset-0 bg-base-content/30 backdrop-blur-sm"
        phx-mounted={
          JS.transition({"transition-opacity duration-200 ease-out", "opacity-0", "opacity-100"},
            time: 200
          )
        }
        phx-remove={
          JS.transition({"transition-opacity duration-150 ease-in", "opacity-100", "opacity-0"},
            time: 150
          )
        }
      >
      </div>
      <div
        class="relative w-full max-w-md rounded-3xl bg-base-100 shadow-2xl border border-base-300 p-6 max-h-[90vh] overflow-y-auto"
        phx-click-away="close_modal"
        phx-mounted={
          JS.transition({"modal-bounce", "opacity-0 scale-90", "opacity-100 scale-100"}, time: 280)
        }
        phx-remove={
          JS.transition({"modal-snap", "opacity-100 scale-100", "opacity-0 scale-95"}, time: 150)
        }
      >
        <div class="flex items-center justify-between mb-3">
          <h3 class="font-display text-3xl text-primary leading-none">{@title}</h3>
          <button
            type="button"
            phx-click="close_modal"
            class="btn btn-circle btn-ghost btn-sm"
            aria-label="Close"
          >
            <.icon name="hero-x-mark" class="size-4" />
          </button>
        </div>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  # ── helpers ──────────────────────────────────────────────────────────────

  defp build_slots do
    Stream.unfold(@display_start_minutes, fn
      m when m >= @display_end_minutes -> nil
      m -> {m, m + Reservation.slot_minutes()}
    end)
    |> Enum.to_list()
  end

  defp format_slot(minutes) do
    h = div(minutes, 60)
    m = rem(minutes, 60)
    :io_lib.format("~2..0B:~2..0B", [h, m]) |> IO.iodata_to_binary()
  end

  defp format_dt(nil), do: ""

  defp format_dt(%DateTime{} = dt) do
    # always render local clock time — guests think in PT, not utc
    %{hour: h, minute: m} = Clock.to_local(dt)
    :io_lib.format("~2..0B:~2..0B", [h, m]) |> IO.iodata_to_binary()
  end

  defp pluralize_people(1), do: "person"
  defp pluralize_people(_), do: "people"

  defp reservation_at(table_id, slot_minutes, availability, date) do
    {:ok, slot_dt} = slot_datetime(date, slot_minutes)

    availability
    |> Map.get(table_id, [])
    |> Enum.find(fn res ->
      DateTime.compare(res.starts_at, slot_dt) in [:lt, :eq] and
        DateTime.compare(res.ends_at, slot_dt) == :gt
    end)
  end

  defp first_slot_of?(nil, _slot_minutes, _date), do: false

  defp first_slot_of?(%Reservation{starts_at: starts}, slot_minutes, date) do
    {:ok, slot_dt} = slot_datetime(date, slot_minutes)
    DateTime.compare(starts, slot_dt) == :eq
  end

  defp slot_datetime(date, slot_minutes) do
    h = div(slot_minutes, 60)
    m = rem(slot_minutes, 60)
    {:ok, time} = Time.new(h, m, 0)
    # the slot grid is local-time labels (06:00–22:00). build the local
    # datetime, then convert to utc for storage/comparison parity.
    {:ok, Clock.local_to_utc(date, time)}
  end

  defp refresh_availability(socket) do
    Reservations.availability_for_date(socket.assigns.selected_date)
  end

  defp open_manage_modal(socket, reservation) do
    has_token? = Map.has_key?(socket.assigns.my_tokens, reservation.id)

    socket
    |> assign(:modal, :manage)
    |> assign(:managing, reservation)
    |> assign(:manage_error, nil)
    |> assign(:manage_mode, if(has_token?, do: :edit, else: :view))
    |> assign(:manage_form, if(has_token?, do: build_edit_form(reservation), else: nil))
  end

  defp build_edit_form(%Reservation{} = res) do
    res
    |> Reservation.changeset(%{})
    |> Map.put(:action, nil)
    |> to_form(as: "reservation")
  end

  # the form sends user-typed name, dietary, notes, party_size; table_id and
  # starts_at come from the modal context (set when the user clicked the cell)
  defp merge_context(params, %{table_id: table_id, starts_at: starts_at}) do
    params
    |> Map.put_new("table_id", table_id)
    |> Map.put_new("starts_at", DateTime.to_iso8601(starts_at))
  end

  # build the {label, value} options for the start-time select used in edit
  defp start_time_options(date, slots) do
    last_start = Reservation.last_start_hour() * 60

    for minutes <- slots, minutes <= last_start do
      {:ok, dt} = slot_datetime(date, minutes)
      {format_slot(minutes), DateTime.to_iso8601(dt)}
    end
  end
end
