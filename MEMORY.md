# MEMORY.md

Permanent project decisions. Read at the start of every session.

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
