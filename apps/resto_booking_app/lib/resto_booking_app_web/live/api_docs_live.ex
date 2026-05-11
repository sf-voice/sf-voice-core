defmodule RestoBookingAppWeb.ApiDocsLive do
  @moduledoc """
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
            Everything the website does is also available over HTTP. Every
            <code>/api/*</code> endpoint is gated by a single shared bearer
            token (<code>INTERNAL_API_TOKEN</code>) — the voice orchestrator
            (ellie_ai) is the only legitimate caller in v1.
          </p>
        </div>

        <div class="rounded-2xl bg-primary/10 border border-primary/40 p-4 mb-6 text-sm">
          <div class="font-bold mb-1">Authentication</div>
          <p class="opacity-90 leading-relaxed">
            Every request to <code>/api/*</code> must carry
            <code>Authorization: Bearer $INTERNAL_API_TOKEN</code>. Missing or
            wrong token returns <code>401 Unauthorized</code>. The token is
            shared via env between resto and ellie; rotate it by setting the
            new value on both services and restarting (no code change needed).
          </p>
          <pre class="rounded-xl bg-base-300/60 p-3 mt-2 text-[11px] overflow-x-auto font-mono">{auth_curl_example()}</pre>
        </div>

        <div class="rounded-2xl bg-secondary/20 border border-secondary/40 p-4 mb-6 text-sm">
          <div class="font-bold mb-1">How cancel tokens work</div>
          <p class="opacity-90 leading-relaxed">
            Bearer auth says "you're allowed to use the API at all." The
            <code>cancel_token</code> says "you specifically own this
            reservation." Both are required to mutate or delete a reservation.
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
              booking is read-only forever — anyone with the bearer can
              <code>GET</code> it, but only the holder of the cancel_token can
              mutate or cancel it.
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
            path="/api/customers"
            desc="List customers, newest activity first. Default limit 500, max 1000."
          >
            <:params>
              <li><code>limit</code> — optional positive integer, max 1000.</li>
            </:params>
            <:response>{customers_index_example()}</:response>
          </.api_card>

          <.api_card
            method="GET"
            path="/api/customers/:id"
            desc="Fetch one customer by id."
          >
            <:params>
              <li><code>:id</code> — customer UUID.</li>
            </:params>
            <:response>{customer_show_example()}</:response>
            <:errors>
              <li><code>404</code> — no customer with that id.</li>
            </:errors>
          </.api_card>

          <.api_card
            method="GET"
            path="/api/customers/by_phone/:phone"
            desc="Look up a customer by E.164 phone number — the natural key. Walks contacts.value → customer. Used by ellie's lookup-customer waterfall when a call comes in."
          >
            <:params>
              <li>
                <code>:phone</code> — E.164 string (URL-encode the leading <code>+</code> as <code>%2B</code>).
              </li>
            </:params>
            <:response>{customer_show_example()}</:response>
            <:errors>
              <li><code>404</code> — no contact with that phone number.</li>
            </:errors>
          </.api_card>

          <.api_card
            method="POST"
            path="/api/customers"
            desc="Idempotent on phone. Creates a new customer + phone contact if the phone is unseen, otherwise returns the existing customer. If email is provided and the customer has no email contact, adds one. Safe to retry."
          >
            <:params>
              <li><code>phone</code> — required, E.164 string.</li>
              <li><code>first_name</code>, <code>last_name</code> — optional.</li>
              <li>
                <code>salutation</code> — optional, one of <code>Mr</code>, <code>Mrs</code>, <code>Ms</code>.
              </li>
              <li>
                <code>email</code> — optional. When provided and unseen, creates a preferred email contact.
              </li>
              <li><code>notes</code> — optional staff free text.</li>
            </:params>
            <:request>{customer_create_request_example()}</:request>
            <:response>{customer_show_example()}</:response>
            <:errors>
              <li><code>400 Missing phone</code> — request body had no <code>phone</code>.</li>
              <li>
                <code>422 phone must be in E.164 format</code> — leading <code>+</code>, then 7..15 digits, first non-zero.
              </li>
              <li><code>422 must look like an email address</code>.</li>
            </:errors>
          </.api_card>

          <.api_card
            method="PATCH"
            path="/api/customers/:id"
            desc="Update a customer's name, email, salutation, or notes. tel is the natural key — change it via a new POST instead."
          >
            <:params>
              <li><code>:id</code> — customer UUID.</li>
            </:params>
            <:request>{customer_patch_request_example()}</:request>
            <:response>{customer_show_example()}</:response>
            <:errors>
              <li><code>404 Not Found</code>.</li>
              <li><code>422</code> — same validation family as POST.</li>
            </:errors>
          </.api_card>

          <.api_card
            method="GET"
            path="/api/customers/:customer_id/reservations"
            desc="List one customer's reservations, oldest first. Same JSON shape as /api/reservations."
          >
            <:params>
              <li><code>:customer_id</code> — customer UUID.</li>
            </:params>
            <:response>{list_example()}</:response>
          </.api_card>

          <.api_card
            method="GET"
            path="/api/reservations[?date=YYYY-MM-DD][&customer_id=UUID]"
            desc="List reservations, optionally filtered to a single calendar day or a single customer."
          >
            <:params>
              <li><code>date</code> — optional, ISO date.</li>
              <li><code>customer_id</code> — optional UUID.</li>
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
            desc="Create a reservation. Bookings are 2 hours, anchored to a 30-min boundary, between 10:00 and 20:00 local time (the restaurant closes at 22:00). The cancel_token in the response is the only way to mutate the reservation later — store it! Customer must already exist; create them via POST /api/customers first."
          >
            <:params>
              <li><code>table_id</code> — required, one of T1..T9.</li>
              <li>
                <code>starts_at</code> — required, ISO datetime on a :00 or :30 boundary, local hour 10..20.
              </li>
              <li>
                <code>customer_id</code> — required UUID.  See <code>POST /api/customers</code>.
              </li>
              <li><code>party_size</code> — required integer, 1..table seats.</li>
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
              <li>
                <code>422 does not exist</code> — <code>customer_id</code> doesn't match any customer.
              </li>
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

  # payloads are plain strings so the docs render verbatim, not as parsed json.

  defp auth_curl_example do
    """
    curl -sH "authorization: Bearer $INTERNAL_API_TOKEN" \\
      https://resto-demo.sf-voice.sh/api/customers
    """
  end

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
              "party_size": 2,
              "special_requests": "gluten free",
              "remarks": null,
              "customer_id": "cust-uuid",
              "customer": { "id": "cust-uuid",
                            "salutation": "Ms",
                            "first_name": "Avery", "last_name": "Chen",
                            "...": "..." },
              "contact_id": "contact-uuid",
              "contact": { "id": "contact-uuid", "kind": "phone",
                           "value": "+14155550142", "preferred": true } }
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
          "party_size": 2,
          "special_requests": "gluten free",
          "remarks": null,
          "customer_id": "cust-uuid",
          "customer": { "id": "cust-uuid", "first_name": "Avery",
                        "last_name": "Chen", "...": "..." },
          "contact_id": "contact-uuid",
          "contact": { "kind": "phone", "value": "+14155550142", "...": "..." } },
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
        "party_size": 2,
        "special_requests": "gluten free",
        "remarks": null,
        "customer_id": "cust-uuid",
        "customer": { "id": "cust-uuid",
                      "salutation": "Ms",
                      "first_name": "Avery", "last_name": "Chen",
                      "notes": null,
                      "first_seen_at": "2026-04-12T19:00:00Z",
                      "last_seen_at":  "2026-05-07T15:00:00Z",
                      "contacts": null },
        "contact_id": "contact-uuid",
        "contact": { "id": "contact-uuid",
                     "customer_id": "cust-uuid",
                     "kind": "phone",
                     "value": "+14155550142",
                     "label": null,
                     "preferred": true }
      }
    }
    """
  end

  defp customers_index_example do
    """
    {
      "customers": [
        { "id": "cust-uuid",
          "salutation": "Ms",
          "first_name": "Lois",
          "last_name": "Tester",
          "notes": null,
          "first_seen_at": "2026-04-12T19:00:00Z",
          "last_seen_at":  "2026-05-08T18:00:00Z",
          "contacts": [
            { "id": "c1", "kind": "phone", "value": "+14155550100",
              "label": null, "preferred": true },
            { "id": "c2", "kind": "email", "value": "lois@example.com",
              "label": null, "preferred": true }
          ] },
        ...
      ]
    }
    """
  end

  defp customer_show_example do
    """
    {
      "customer": {
        "id": "cust-uuid",
        "salutation": "Ms",
        "first_name": "Lois",
        "last_name": "Tester",
        "notes": "regular — vegan",
        "first_seen_at": "2026-04-12T19:00:00Z",
        "last_seen_at":  "2026-05-08T18:00:00Z",
        "contacts": [
          { "id": "c1", "kind": "phone", "value": "+14155550100",
            "label": "mobile", "preferred": true },
          { "id": "c2", "kind": "email", "value": "lois@example.com",
            "label": null, "preferred": true }
        ]
      }
    }
    """
  end

  defp customer_create_request_example do
    """
    {
      "phone": "+14155550100",
      "salutation": "Ms",
      "first_name": "Lois",
      "last_name": "Tester",
      "email": "lois@example.com"
    }
    """
  end

  defp customer_patch_request_example do
    """
    {
      "email": "lois.tester@example.com",
      "notes": "allergic to peanuts"
    }
    """
  end

  defp create_request_example do
    """
    {
      "table_id": "T5",
      "starts_at": "2026-05-08T18:00:00Z",
      "customer_id": "cust-uuid",
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
        "party_size": 3,
        "special_requests": "vegan tasting menu",
        "remarks": null,
        "customer_id": "cust-uuid",
        "customer": { "id": "cust-uuid", "tel": "+14155550100", "...": "..." }
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
        "party_size": 4,
        "special_requests": "vegan + nut allergy",
        "remarks": null,
        "customer_id": "cust-uuid",
        "customer": { "id": "cust-uuid", "...": "..." }
      }
    }
    """
  end

  defp put_request_example do
    """
    {
      "table_id": "T5",
      "starts_at": "2026-05-08T19:00:00Z",
      "customer_id": "cust-uuid",
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
        "party_size": 4,
        "special_requests": "vegan + nut allergy",
        "remarks": null,
        "customer_id": "cust-uuid",
        "customer": { "id": "cust-uuid", "...": "..." }
      }
    }
    """
  end

  defp create_curl_example do
    """
    # 1. ensure the customer exists (idempotent on phone) and grab the id
    CUST_ID=$(curl -sX POST localhost:4000/api/customers \\
      -H "authorization: Bearer $INTERNAL_API_TOKEN" \\
      -H 'content-type: application/json' \\
      -d '{"phone":"+14155550100","first_name":"Lois","last_name":"Tester","email":"lois@example.com"}' \\
      | jq -r .customer.id)

    # 2. book — capture both id and cancel_token from the response
    curl -sX POST localhost:4000/api/reservations \\
      -H "authorization: Bearer $INTERNAL_API_TOKEN" \\
      -H 'content-type: application/json' \\
      -d "{
        \\"table_id\\": \\"T5\\",
        \\"starts_at\\": \\"2026-05-08T18:00:00Z\\",
        \\"customer_id\\": \\"$CUST_ID\\",
        \\"party_size\\": 3,
        \\"special_requests\\": \\"vegan\\"
      }"
    # → { "reservation": { "id": "...", "cancel_token": "...", ... } }
    """
  end

  defp patch_curl_example do
    """
    # ID and TOKEN come from the POST /api/reservations response above
    ID="69f3b15c-d7b4-42ea-a319-d99a2f766fd8"
    TOKEN="QMyYa1Iv4c5Rs7Itx3VPtg"

    curl -sX PATCH "localhost:4000/api/reservations/$ID?token=$TOKEN" \\
      -H "authorization: Bearer $INTERNAL_API_TOKEN" \\
      -H 'content-type: application/json' \\
      -d '{ "party_size": 4, "special_requests": "vegan + nut allergy" }'
    """
  end

  defp put_curl_example do
    """
    # PUT requires all the required fields. ID and TOKEN are still from POST.
    curl -sX PUT "localhost:4000/api/reservations/$ID?token=$TOKEN" \\
      -H "authorization: Bearer $INTERNAL_API_TOKEN" \\
      -H 'content-type: application/json' \\
      -d "{
        \\"table_id\\": \\"T5\\",
        \\"starts_at\\": \\"2026-05-08T19:00:00Z\\",
        \\"customer_id\\": \\"$CUST_ID\\",
        \\"party_size\\": 4,
        \\"special_requests\\": \\"vegan + nut allergy\\"
      }"
    """
  end

  defp delete_curl_example do
    """
    # same TOKEN as PATCH/PUT — there's only ever one per reservation
    curl -i -X DELETE "localhost:4000/api/reservations/$ID?token=$TOKEN" \\
      -H "authorization: Bearer $INTERNAL_API_TOKEN"
    # → HTTP/1.1 204 No Content
    """
  end
end
