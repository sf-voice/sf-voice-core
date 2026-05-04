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
