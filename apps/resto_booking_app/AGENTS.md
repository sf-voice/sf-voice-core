# RestoBookingApp — agent rules

App-specific rules for `apps/resto_booking_app`. Read after the repo-root `AGENTS.md`.

**Stack rules:** Phoenix/Elixir conventions live in [`../ELIXIR_RULES.md`](../ELIXIR_RULES.md). Read both before working in this app.

**Decisions:** [`MEMORY.md`](MEMORY.md) holds resto-specific decisions. Cross-app boundary decisions (ellie ↔ resto) live in [`../ellie_ai/MEMORY.md`](../ellie_ai/MEMORY.md). Read both before touching code that crosses the boundary.

---

## Scope

Resto is the reservation system and customer records store for **The Seasons Restaurant Group**. Multi-tenant within one deploy: each restaurant location is an `org`, scoped by `org_slug` in the URL path.

What resto owns:
- `orgs`, `customers`, `contacts`, `reservations`, `tables`, `menu_items`.
- The `/floor_plan` UI for guest bookings.
- A path-scoped read API for ellie to poll (`/api/orgs/:org_slug/customers/...`).

What resto does **not** own:
- Telnyx integration. Ellie owns all of it.
- Outbound HTTP. Resto never calls ellie. Resto has no `:req` dep, no `EllieClient`.
- Staff UI. All staff pages live on ellie.

Resto's container env is minimal: `INTERNAL_API_TOKEN` only. Ellie polls resto; resto is oblivious to whether ellie is up.

---

## Audience

Restaurant guests booking tables. Assume **very low technical literacy**. Every action must be obvious from the screen alone — no clever interactions, no hidden affordances, no jargon. If a feature needs a tooltip or tutorial to be usable, redesign it.

The booking site is **always reachable**, independent of restaurant opening hours. Guests can submit a reservation at 3am on a Sunday. Opening hours constrain which *slots* are bookable, not *when* the booking can be made. See `MEMORY.md` (2026-05-04).

---

## URL convention

Every `/api/*` URL is path-scoped by org slug: `GET /api/orgs/seasons-sf/customers/by_phone/+1...`, `POST /api/orgs/seasons-sf/customers`. The `OrgScope` plug resolves `:org_slug` → `org_id` once at the top of every controller action, then every query filters by `org_id`. No header-based scoping.

The floor plan UI is also path-scoped: `/:org_slug/floor_plan`.

See `MEMORY.md` (2026-05-09) for the decision history.
