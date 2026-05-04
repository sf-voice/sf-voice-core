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

      <.api_reference />

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
      phx-click-away="close_modal"
      phx-window-keydown="close_modal"
      phx-key="escape"
    >
      <div class="absolute inset-0 bg-base-content/30 backdrop-blur-sm"></div>
      <div class="relative w-full max-w-md rounded-3xl bg-base-100 shadow-2xl border border-base-300 p-6 max-h-[90vh] overflow-y-auto">
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

  defp api_reference(assigns) do
    ~H"""
    <section id="api" class="mt-12">
      <div class="mb-4">
        <h2 class="font-display text-3xl text-primary">api reference</h2>
        <p class="text-sm opacity-70">
          Everything the website does is also available over HTTP. Have at it.
        </p>
      </div>

      <div class="rounded-2xl bg-secondary/20 border border-secondary/40 p-4 mb-6 text-sm">
        <div class="font-bold mb-1">How cancel tokens work</div>
        <p class="opacity-90 leading-relaxed">
          There are no accounts, no API keys, no logins. The only way to prove
          you own a reservation is to hold the <code>cancel_token</code> the
          server returned at booking time.
        </p>
        <ol class="list-decimal pl-5 mt-2 space-y-1 opacity-90">
          <li>
            <code>POST /api/reservations</code> creates a row and the response
            body includes both an <code>id</code> and a <code>cancel_token</code>.
            That token is shown <strong>once</strong>, in that response — it's
            the only place the server will ever hand it to you.
          </li>
          <li>
            Save it. Pass it as <code>?token=&lt;value&gt;</code>
            on every <code>PATCH</code>, <code>PUT</code>, or <code>DELETE</code>
            for
            that reservation's <code>:id</code>.
          </li>
          <li>
            There's no token recovery and no admin override. Lose it and the
            booking is read-only forever — anyone can <code>GET</code> it, but
            only the holder of the original token can mutate or cancel it.
          </li>
        </ol>
        <div class="mt-3 text-xs opacity-80">
          The browser stashes tokens for bookings made on this device in <code>localStorage["nibble:tokens"]</code>, so the website's
          edit/cancel buttons work without re-pasting. The HTTP API has no
          such convenience — you carry the token yourself.
        </div>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <.api_card
          method="GET"
          path="/api/menu"
          desc="Three services (breakfast / lunch / dinner) with prices in cents and dietary tags."
        >
          <:response>{menu_example()}</:response>
        </.api_card>

        <.api_card
          method="GET"
          path="/api/tables"
          desc="The static floor plan — 9 tables totalling 30 seats."
        >
          <:response>{tables_example()}</:response>
        </.api_card>

        <.api_card
          method="GET"
          path="/api/availability?date=YYYY-MM-DD"
          desc="Per-table list of taken intervals for a date. Empty list means the table is free all day."
        >
          <:params>
            <li><code>date</code> — optional, ISO date. Defaults to today (UTC).</li>
          </:params>
          <:response>{availability_example()}</:response>
          <:errors>
            <li><code>400</code> — <code>date</code> isn't a valid ISO date.</li>
          </:errors>
        </.api_card>

        <.api_card
          method="GET"
          path="/api/reservations[?date=YYYY-MM-DD]"
          desc="List reservations, optionally filtered to a single calendar day (UTC)."
        >
          <:params>
            <li><code>date</code> — optional, ISO date.</li>
          </:params>
          <:response>{list_example()}</:response>
          <:errors>
            <li><code>400</code> — bad <code>date</code>.</li>
          </:errors>
        </.api_card>

        <.api_card
          method="GET"
          path="/api/reservations/:id"
          desc="Fetch a single reservation. The cancel_token is never returned by this endpoint — only on creation."
        >
          <:params>
            <li><code>:id</code> — UUID returned at booking time.</li>
          </:params>
          <:response>{show_example()}</:response>
          <:errors>
            <li><code>404</code> — no reservation with that id.</li>
          </:errors>
        </.api_card>

        <.api_card
          method="POST"
          path="/api/reservations"
          desc="Create a reservation. Bookings are 2 hours, anchored to a 30-min boundary, between 06:00 and 20:00 UTC. The cancel_token in the response is the only way to mutate the reservation later — store it!"
        >
          <:params>
            <li><code>table_id</code> — required, one of T1..T9.</li>
            <li>
              <code>starts_at</code> — required, ISO datetime on a :00 or :30 boundary, hour 6..20.
            </li>
            <li><code>name</code> — required.</li>
            <li><code>party_size</code> — required integer, 1..table seats.</li>
            <li><code>dietary</code> — optional free text.</li>
          </:params>
          <:request>{create_request_example()}</:request>
          <:response>{create_response_example()}</:response>
          <:example>{create_curl_example()}</:example>
          <:errors>
            <li>
              <code>422 unknown table T999</code> — <code>table_id</code> not in the floor plan.
            </li>
            <li>
              <code>422 must align to a 30-minute slot</code> — bad <code>starts_at</code> minutes.
            </li>
            <li><code>422 must be between 06:00 and 20:00</code> — out of hours.</li>
            <li><code>422 table is already booked for this time slot</code> — overlap.</li>
            <li><code>422 must be greater than 0</code> — non-positive <code>party_size</code>.</li>
            <li><code>422 is more than the table's N seats</code> — too many for this table.</li>
            <li><code>422 can't be blank</code> — missing required field.</li>
          </:errors>
        </.api_card>

        <.api_card
          method="PATCH"
          path="/api/reservations/:id?token=…"
          desc="Partial update. Send any subset of table_id, starts_at, name, party_size, or dietary. The same validations as create apply, plus an overlap check that excludes the row being updated."
        >
          <:params>
            <li>
              <code>:id</code> — reservation UUID returned by <code>POST /api/reservations</code>.
            </li>
            <li>
              <code>token</code>
              — required query param. Pass the <code>cancel_token</code>
              string from the original <code>POST</code>
              response. Same value as long as the
              reservation exists; never rotated.
            </li>
          </:params>
          <:request>{patch_request_example()}</:request>
          <:response>{patch_response_example()}</:response>
          <:example>{patch_curl_example()}</:example>
          <:errors>
            <li>
              <code>400 Missing token query parameter</code> — you forgot <code>?token=…</code>.
            </li>
            <li><code>403 Invalid cancel token</code> — token doesn't match this reservation.</li>
            <li>
              <code>404 Not Found</code>
              — no reservation with that <code>:id</code>
              (or it was already cancelled).
            </li>
            <li><code>422</code> — same family of validation errors as POST.</li>
          </:errors>
        </.api_card>

        <.api_card
          method="PUT"
          path="/api/reservations/:id?token=…"
          desc="Full replace. Same handler as PATCH — Phoenix routes both verbs to the update action. Send all four mutable fields."
        >
          <:params>
            <li><code>:id</code> — reservation UUID from the original <code>POST</code> response.</li>
            <li>
              <code>token</code>
              — required query param. The <code>cancel_token</code>
              from <code>POST /api/reservations</code>
              — same value used by PATCH and DELETE.
            </li>
          </:params>
          <:request>{put_request_example()}</:request>
          <:response>{put_response_example()}</:response>
          <:example>{put_curl_example()}</:example>
          <:errors>
            <li><code>400 Missing token query parameter</code>.</li>
            <li><code>403 Invalid cancel token</code>.</li>
            <li><code>404 Not Found</code>.</li>
            <li>
              <code>422</code>
              — same validation errors as POST (alignment, hours, table fit, overlap).
            </li>
          </:errors>
        </.api_card>

        <.api_card
          method="DELETE"
          path="/api/reservations/:id?token=…"
          desc="Cancel a reservation. Constant-time token check — bad tokens get a 403, not a 404."
        >
          <:params>
            <li><code>:id</code> — reservation UUID from the <code>POST</code> response.</li>
            <li>
              <code>token</code>
              — required query param. The <code>cancel_token</code>
              from <code>POST /api/reservations</code>. Once the reservation is
              deleted the token is gone too — no undo.
            </li>
          </:params>
          <:response>204 No Content (empty body)</:response>
          <:example>{delete_curl_example()}</:example>
          <:errors>
            <li><code>400 Missing token query parameter</code>.</li>
            <li><code>403 Invalid cancel token</code>.</li>
            <li><code>404 Not Found</code>.</li>
          </:errors>
        </.api_card>
      </div>
    </section>
    """
  end

  # ── api reference example payloads ───────────────────────────────────────
  # kept as plain strings so the docs render verbatim, not as fake json

  defp menu_example do
    """
    {
      "services": [
        {
          "service": "breakfast",
          "items": [
            { "name": "Sourdough Toast & Jam",
              "price_cents": 700,
              "dietary": ["vegan"] },
            ...
          ]
        },
        { "service": "lunch",   "items": [...] },
        { "service": "dinner",  "items": [...] }
      ]
    }
    """
  end

  defp tables_example do
    """
    {
      "seat_total": 30,
      "tables": [
        { "id": "T1", "seats": 2, "shape": "round",  "x": 0, "y": 0 },
        ...
        { "id": "T9", "seats": 6, "shape": "rect",   "x": 0, "y": 2 }
      ]
    }
    """
  end

  defp availability_example do
    """
    {
      "date": "2026-05-04",
      "tables": [
        {
          "table_id": "T1",
          "reservations": [
            { "id": "uuid",
              "table_id": "T1",
              "starts_at": "2026-05-04T08:00:00Z",
              "ends_at":   "2026-05-04T10:00:00Z",
              "name": "Avery Chen",
              "dietary": "gluten free",
              "party_size": 2 }
          ]
        },
        { "table_id": "T2", "reservations": [] },
        ...
      ]
    }
    """
  end

  defp list_example do
    """
    {
      "reservations": [
        { "id": "uuid",
          "table_id": "T1",
          "starts_at": "2026-05-04T08:00:00Z",
          "ends_at":   "2026-05-04T10:00:00Z",
          "name": "Avery Chen",
          "dietary": "gluten free",
          "party_size": 2 },
        ...
      ]
    }
    """
  end

  defp show_example do
    """
    {
      "reservation": {
        "id": "uuid",
        "table_id": "T1",
        "starts_at": "2026-05-04T08:00:00Z",
        "ends_at":   "2026-05-04T10:00:00Z",
        "name": "Avery Chen",
        "dietary": "gluten free",
        "party_size": 2
      }
    }
    """
  end

  defp create_request_example do
    """
    {
      "table_id": "T5",
      "starts_at": "2026-05-04T18:00:00Z",
      "name": "Lois",
      "party_size": 3,
      "dietary": "vegan"
    }
    """
  end

  defp create_response_example do
    """
    {
      "reservation": {
        "id": "uuid",
        "cancel_token": "QMyYa1Iv4c5Rs7Itx3VPtg",
        "table_id": "T5",
        "starts_at": "2026-05-04T18:00:00Z",
        "ends_at":   "2026-05-04T20:00:00Z",
        "name": "Lois",
        "party_size": 3,
        "dietary": "vegan"
      }
    }
    """
  end

  defp patch_request_example do
    """
    {
      "starts_at": "2026-05-04T19:00:00Z",
      "party_size": 4,
      "dietary": "vegan + nut allergy"
    }
    """
  end

  defp patch_response_example do
    """
    {
      "reservation": {
        "id": "uuid",
        "table_id": "T5",
        "starts_at": "2026-05-04T19:00:00Z",
        "ends_at":   "2026-05-04T21:00:00Z",
        "name": "Lois",
        "party_size": 4,
        "dietary": "vegan + nut allergy"
      }
    }
    """
  end

  defp put_request_example do
    """
    {
      "table_id": "T5",
      "starts_at": "2026-05-04T19:00:00Z",
      "name": "Lois",
      "party_size": 4,
      "dietary": "vegan + nut allergy"
    }
    """
  end

  defp put_response_example do
    """
    {
      "reservation": {
        "id": "uuid",
        "table_id": "T5",
        "starts_at": "2026-05-04T19:00:00Z",
        "ends_at":   "2026-05-04T21:00:00Z",
        "name": "Lois",
        "party_size": 4,
        "dietary": "vegan + nut allergy"
      }
    }
    """
  end

  # ── runnable curl recipes ─────────────────────────────────────────────────
  # these use placeholder $ID and $TOKEN so users see exactly what the chain
  # looks like end-to-end: capture them from POST, then reuse them.

  defp create_curl_example do
    """
    # the response prints both id and cancel_token — capture them:
    curl -sX POST localhost:4000/api/reservations \\
      -H 'content-type: application/json' \\
      -d '{
        "table_id": "T5",
        "starts_at": "2026-05-04T18:00:00Z",
        "name": "Lois",
        "party_size": 3,
        "dietary": "vegan"
      }'
    # → { "reservation": { "id": "...", "cancel_token": "...", ... } }
    """
  end

  defp patch_curl_example do
    """
    # ID and TOKEN come from the POST response above
    ID="69f3b15c-d7b4-42ea-a319-d99a2f766fd8"
    TOKEN="QMyYa1Iv4c5Rs7Itx3VPtg"

    curl -sX PATCH "localhost:4000/api/reservations/$ID?token=$TOKEN" \\
      -H 'content-type: application/json' \\
      -d '{ "party_size": 4, "dietary": "vegan + nut allergy" }'
    """
  end

  defp put_curl_example do
    """
    # PUT requires all four mutable fields. ID and TOKEN are still from POST.
    curl -sX PUT "localhost:4000/api/reservations/$ID?token=$TOKEN" \\
      -H 'content-type: application/json' \\
      -d '{
        "table_id": "T5",
        "starts_at": "2026-05-04T19:00:00Z",
        "name": "Lois",
        "party_size": 4,
        "dietary": "vegan + nut allergy"
      }'
    """
  end

  defp delete_curl_example do
    """
    # same TOKEN as PATCH/PUT — there's only ever one per reservation
    curl -i -X DELETE "localhost:4000/api/reservations/$ID?token=$TOKEN"
    # → HTTP/1.1 204 No Content
    """
  end

  attr :method, :string, required: true
  attr :path, :string, required: true
  attr :desc, :string, required: true
  slot :params
  slot :request
  slot :response
  slot :example
  slot :errors

  defp api_card(assigns) do
    ~H"""
    <details class="rounded-2xl bg-base-100/90 border border-base-300 p-4 group">
      <summary class="cursor-pointer flex flex-wrap items-center gap-2 list-none">
        <span class={["api-method", "api-method-#{String.downcase(@method)}"]}>
          {@method}
        </span>
        <code class="font-mono text-xs sm:text-sm flex-1 break-all">{@path}</code>
        <span class="opacity-40 text-xs group-open:rotate-90 transition-transform">▶</span>
      </summary>

      <p class="text-sm opacity-80 mt-3">{@desc}</p>

      <div :if={@params != []} class="mt-3">
        <div class="text-[10px] uppercase tracking-wider opacity-60 font-semibold mb-1">
          Parameters
        </div>
        <ul class="list-disc pl-5 text-xs space-y-0.5">{render_slot(@params)}</ul>
      </div>

      <div :if={@request != []} class="mt-3">
        <div class="text-[10px] uppercase tracking-wider opacity-60 font-semibold mb-1">
          Request body
        </div>
        <pre class="rounded-xl bg-base-300/60 p-3 text-[11px] overflow-x-auto font-mono">{render_slot(@request)}</pre>
      </div>

      <div :if={@response != []} class="mt-3">
        <div class="text-[10px] uppercase tracking-wider opacity-60 font-semibold mb-1">Response</div>
        <pre class="rounded-xl bg-base-300/60 p-3 text-[11px] overflow-x-auto font-mono">{render_slot(@response)}</pre>
      </div>

      <div :if={@example != []} class="mt-3">
        <div class="text-[10px] uppercase tracking-wider opacity-60 font-semibold mb-1">
          Example (curl)
        </div>
        <pre class="rounded-xl bg-base-300/60 p-3 text-[11px] overflow-x-auto font-mono">{render_slot(@example)}</pre>
      </div>

      <div :if={@errors != []} class="mt-3">
        <div class="text-[10px] uppercase tracking-wider opacity-60 font-semibold mb-1">Errors</div>
        <ul class="list-disc pl-5 text-xs space-y-0.5">{render_slot(@errors)}</ul>
      </div>
    </details>
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
