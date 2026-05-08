defmodule RestoBookingAppWeb.ApiDocsLive do
  @moduledoc """
  developer-facing http api reference. lives at /api so it stays out of
  the way of guests landing on / to book a table.
  """

  use RestoBookingAppWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "API")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="mb-6">
        <.link href="/" class="text-sm opacity-60 hover:opacity-100">← back to floor plan</.link>
      </section>

      <section>
        <div class="mb-6">
          <p class="text-[10px] uppercase tracking-[0.3em] text-primary opacity-70 mb-2">
            For developers
          </p>
          <h1 class="font-display text-4xl sm:text-5xl text-base-content leading-tight">
            HTTP API reference
          </h1>
          <p class="text-sm opacity-70 mt-3 max-w-2xl leading-relaxed">
            Everything the website does is also available over HTTP. The
            endpoints below are the same surface the floor plan uses — public,
            unauthenticated, and stable.
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
              for that reservation's <code>:id</code>.
            </li>
            <li>
              There's no token recovery and no admin override. Lose it and the
              booking is read-only forever — anyone can <code>GET</code> it, but
              only the holder of the original token can mutate or cancel it.
            </li>
          </ol>
          <div class="mt-3 text-xs opacity-80">
            The browser stashes tokens for bookings made on this device in <code>localStorage["seasons:tokens"]</code>, so the website's
            edit/cancel buttons work without re-pasting. The HTTP API has no
            such convenience — you carry the token yourself.
          </div>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <.api_card
            method="GET"
            path="/api/menu"
            desc="Three services (breakfast / lunch / dinner) with prices in cents and dietary tags on each menu item."
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
              <li><code>date</code> — optional, ISO date. Defaults to today.</li>
            </:params>
            <:response>{availability_example()}</:response>
            <:errors>
              <li><code>400</code> — <code>date</code> isn't a valid ISO date.</li>
            </:errors>
          </.api_card>

          <.api_card
            method="GET"
            path="/api/reservations[?date=YYYY-MM-DD]"
            desc="List reservations, optionally filtered to a single calendar day."
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
            desc="Create a reservation. Bookings are 2 hours, anchored to a 30-min boundary, between 10:00 and 20:00 local time (the restaurant closes at 22:00). The cancel_token in the response is the only way to mutate the reservation later — store it!"
          >
            <:params>
              <li><code>table_id</code> — required, one of T1..T9.</li>
              <li>
                <code>starts_at</code> — required, ISO datetime on a :00 or :30 boundary, local hour 10..20.
              </li>
              <li><code>first_name</code> — required.</li>
              <li><code>last_name</code> — required.</li>
              <li><code>tel</code> — required.</li>
              <li><code>email</code> — required.</li>
              <li><code>party_size</code> — required integer, 1..table seats.</li>
              <li>
                <code>salutation</code> — optional, one of <code>Mr</code>, <code>Mrs</code>, <code>Ms</code>.
              </li>
              <li><code>special_requests</code> — optional free text.</li>
              <li><code>remarks</code> — optional free text.</li>
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
              <li><code>422 must be between 10:00 and 20:00</code> — outside opening hours.</li>
              <li><code>422 table is already booked for this time slot</code> — overlap.</li>
              <li><code>422 must look like an email address</code> — bad <code>email</code>.</li>
              <li><code>422 must be greater than 0</code> — non-positive <code>party_size</code>.</li>
              <li><code>422 is more than the table's N seats</code> — too many for this table.</li>
              <li><code>422 can't be blank</code> — missing required field.</li>
            </:errors>
          </.api_card>

          <.api_card
            method="PATCH"
            path="/api/reservations/:id?token=…"
            desc="Partial update. Send any subset of the booking fields. The same validations as create apply, plus an overlap check that excludes the row being updated."
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
            desc="Full replace. Same handler as PATCH — Phoenix routes both verbs to the update action. Send all required fields."
          >
            <:params>
              <li>
                <code>:id</code> — reservation UUID from the original <code>POST</code> response.
              </li>
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
                — same validation errors as POST (alignment, table fit, overlap, missing fields).
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
    </Layouts.app>
    """
  end

  # ── api card ─────────────────────────────────────────────────────────────

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

  # ── example payloads ─────────────────────────────────────────────────────
  # plain strings so the docs render verbatim, not as fake json

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
      "date": "2026-05-07",
      "tables": [
        {
          "table_id": "T1",
          "reservations": [
            { "id": "uuid",
              "table_id": "T1",
              "starts_at": "2026-05-07T15:00:00Z",
              "ends_at":   "2026-05-07T17:00:00Z",
              "salutation": "Ms",
              "first_name": "Avery",
              "last_name":  "Chen",
              "tel":        "+1-415-555-0142",
              "email":      "avery.chen@example.com",
              "party_size": 2,
              "special_requests": "gluten free",
              "remarks": null }
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
          "starts_at": "2026-05-07T15:00:00Z",
          "ends_at":   "2026-05-07T17:00:00Z",
          "salutation": "Ms",
          "first_name": "Avery",
          "last_name":  "Chen",
          "tel":        "+1-415-555-0142",
          "email":      "avery.chen@example.com",
          "party_size": 2,
          "special_requests": "gluten free",
          "remarks": null },
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
        "starts_at": "2026-05-07T15:00:00Z",
        "ends_at":   "2026-05-07T17:00:00Z",
        "salutation": "Ms",
        "first_name": "Avery",
        "last_name":  "Chen",
        "tel":        "+1-415-555-0142",
        "email":      "avery.chen@example.com",
        "party_size": 2,
        "special_requests": "gluten free",
        "remarks": null
      }
    }
    """
  end

  defp create_request_example do
    """
    {
      "table_id": "T5",
      "starts_at": "2026-05-08T18:00:00Z",
      "salutation": "Ms",
      "first_name": "Lois",
      "last_name": "Tester",
      "tel": "+1-415-555-0100",
      "email": "lois@example.com",
      "party_size": 3,
      "special_requests": "vegan tasting menu"
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
        "starts_at": "2026-05-08T18:00:00Z",
        "ends_at":   "2026-05-08T20:00:00Z",
        "salutation": "Ms",
        "first_name": "Lois",
        "last_name":  "Tester",
        "tel":        "+1-415-555-0100",
        "email":      "lois@example.com",
        "party_size": 3,
        "special_requests": "vegan tasting menu",
        "remarks": null
      }
    }
    """
  end

  defp patch_request_example do
    """
    {
      "starts_at": "2026-05-08T19:00:00Z",
      "party_size": 4,
      "special_requests": "vegan + nut allergy"
    }
    """
  end

  defp patch_response_example do
    """
    {
      "reservation": {
        "id": "uuid",
        "table_id": "T5",
        "starts_at": "2026-05-08T19:00:00Z",
        "ends_at":   "2026-05-08T21:00:00Z",
        "salutation": "Ms",
        "first_name": "Lois",
        "last_name":  "Tester",
        "tel":        "+1-415-555-0100",
        "email":      "lois@example.com",
        "party_size": 4,
        "special_requests": "vegan + nut allergy",
        "remarks": null
      }
    }
    """
  end

  defp put_request_example do
    """
    {
      "table_id": "T5",
      "starts_at": "2026-05-08T19:00:00Z",
      "salutation": "Ms",
      "first_name": "Lois",
      "last_name": "Tester",
      "tel": "+1-415-555-0100",
      "email": "lois@example.com",
      "party_size": 4,
      "special_requests": "vegan + nut allergy"
    }
    """
  end

  defp put_response_example do
    """
    {
      "reservation": {
        "id": "uuid",
        "table_id": "T5",
        "starts_at": "2026-05-08T19:00:00Z",
        "ends_at":   "2026-05-08T21:00:00Z",
        "salutation": "Ms",
        "first_name": "Lois",
        "last_name":  "Tester",
        "tel":        "+1-415-555-0100",
        "email":      "lois@example.com",
        "party_size": 4,
        "special_requests": "vegan + nut allergy",
        "remarks": null
      }
    }
    """
  end

  defp create_curl_example do
    """
    # the response prints both id and cancel_token — capture them:
    curl -sX POST localhost:4000/api/reservations \\
      -H 'content-type: application/json' \\
      -d '{
        "table_id": "T5",
        "starts_at": "2026-05-08T18:00:00Z",
        "salutation": "Ms",
        "first_name": "Lois",
        "last_name": "Tester",
        "tel": "+1-415-555-0100",
        "email": "lois@example.com",
        "party_size": 3,
        "special_requests": "vegan"
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
      -d '{ "party_size": 4, "special_requests": "vegan + nut allergy" }'
    """
  end

  defp put_curl_example do
    """
    # PUT requires all the required fields. ID and TOKEN are still from POST.
    curl -sX PUT "localhost:4000/api/reservations/$ID?token=$TOKEN" \\
      -H 'content-type: application/json' \\
      -d '{
        "table_id": "T5",
        "starts_at": "2026-05-08T19:00:00Z",
        "salutation": "Ms",
        "first_name": "Lois",
        "last_name": "Tester",
        "tel": "+1-415-555-0100",
        "email": "lois@example.com",
        "party_size": 4,
        "special_requests": "vegan + nut allergy"
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
end
