# apps/resto_booking_app/MEMORY.md

Decisions specific to `apps/resto_booking_app`.

Repo-wide conventions live in repo-root `AGENTS.md`. Apps-wide conventions live in `../MEMORY.md`. Stack rules live in `../ELIXIR_RULES.md`.

**Cross-app boundary decisions** (how resto talks to ellie, what each app owns, multi-tenancy, etc.) live in [`../ellie_ai/MEMORY.md`](../ellie_ai/MEMORY.md). Ellie is the primary actor across the boundary; resto exposes endpoints and ellie consumes them. Read ellie's MEMORY when touching code that crosses the boundary.

Read this file before doing any work in `apps/resto_booking_app`.

---

## 2026-05-04 — Booking site is available 24/7

**What was decided:** The booking website is always reachable, independent of restaurant opening hours. Guests can submit a reservation at any time of day or night (3am, Sunday morning, etc.), even when The Seasons is closed.

**Why:** Guests think about dinner plans at all hours. Forcing them to wait until the restaurant is "open" to submit a booking loses reservations. The website is a 24/7 surface; the restaurant's physical hours only constrain *which time slots* are bookable, not *when* the booking can be made.

**What was rejected:** Interpretation #2 — letting guests book a table for any hour (e.g. 3am dining). The Seasons is not a 24/7 restaurant. Opening hours still constrain bookable slots.

**Implications for implementation:**
- Booking submissions must persist cleanly outside opening hours — no dependency on staff being online to accept them.
- Confirmation flow cannot assume immediate human response. Either auto-confirm on valid slots, or clearly tell the guest "we'll confirm by email in the morning."
- The booking flow must never show a "we're closed, come back later" wall.
- Opening hours are a constraint on the *slot picker*, not on access to the site.

---

## 2026-05-04 — Production hostname is `resto-demo.sf-voice.sh` (2nd-level, not 3rd)

**What was decided:** The demo site lives at `resto-demo.sf-voice.sh`, not `resto-demo.do.sf-voice.sh`.

**Why:** Cloudflare's free Universal SSL only covers the apex (`sf-voice.sh`) and one wildcard level (`*.sf-voice.sh`). A 3rd-level subdomain like `resto-demo.do.sf-voice.sh` triggers `ERR_SSL_VERSION_OR_CIPHER_MISMATCH` at the browser because the Cloudflare edge has no matching cert. Confirmed by hitting the hostname in Chrome and seeing the error firsthand.

**What was rejected:** (1) Cloudflare Advanced Certificate Manager (~$10/mo) — overkill for a single demo. (2) Cloudflare Pro plan with Total TLS ($25/mo) — not justified at this scale.

**Implications for implementation:**
- All future demo apps under `sf-voice.sh` should use 2nd-level subdomains (e.g. `app2.sf-voice.sh`), not deeper.
- The Cloudflare origin cert on the droplet must cover `*.sf-voice.sh` (not `*.do.sf-voice.sh`). Issued via Cloudflare → SSL/TLS → Origin Server.
- If we ever need namespacing by host provider again, do it via the app name (`resto-do`, `resto-fly`) rather than a subdomain layer.

---

## 2026-05-09 — Resto API surface is path-scoped by org slug

**What was decided:** Every resto `/api/*` URL gains an `:org_slug` segment: `GET /api/orgs/seasons-sf/customers/by_phone/+1...`, `POST /api/orgs/seasons-sf/customers`, etc. Ellie constructs URLs with the right slug per org. Resto resolves `:org_slug` to `org_id` once at the top of every controller action, then scopes every query.

**Why:** Most explicit option. Every URL says which org it's about — audit logs are obvious; no "I forgot the header" bugs; no chance of cross-org leakage from a missing scope filter. Bearer auth stays a single shared secret across orgs (auth says "you can use the API"; org says "for which restaurant").

**What was rejected:**
- Header-based scoping (`X-Org-Slug: ...`): less explicit, easier to forget on a new endpoint.
- Token-encoded org (one token per org, server resolves): adds key rotation surface and mixes auth with data.

**Implications for implementation:**
- Resto's router scope changes from `/api/...` to `/api/orgs/:org_slug/...`.
- A new `OrgScope` plug resolves `:org_slug` → `org_id`, halts with 404 if unknown, assigns `:org` and `:org_id` to the conn.
- All controllers read `conn.assigns.org_id` and pass it to context calls (e.g. `Customers.list(org_id: org.id, ...)`).
- Ellie's HTTP client (`EllieAi.Resto`) takes the org as its first argument and constructs URLs from `org.resto_base_url` + `/api/orgs/#{org.slug}/...`.
