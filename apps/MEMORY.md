# apps/MEMORY.md

Decisions that apply to **every BEAM app** under `apps/`. Per-app decisions live in each app's own `MEMORY.md`. Cross-cutting decisions between specific apps live in the **primary actor's** `MEMORY.md` (see `apps/ellie_ai/MEMORY.md` and `apps/resto_booking_app/MEMORY.md`).

---

## 2026-05-10 — Shared constants live in per-context `Constants` modules

**What was decided:** When a literal value (domain enum, magic number with business meaning, regex, etc.) is used in two or more modules, it gets extracted to a per-context `Constants` module — `RestoBookingApp.Reservations.Constants`, `RestoBookingApp.Menu.Constants`, `RestoBookingApp.Contacts.Constants`. Cross-context shared values go in a top-level `RestoBookingApp.Validations` module. Values used in only one module stay as `@module_attribute` co-located with the function that uses them. Don't preemptively centralise — wait for the second use.

**Why:** The codebase had genuine duplication (`@e164_regex` and `@email_regex` defined identically in `Bookings` and `Contacts.Contact`) and shared values exposed via ad-hoc accessors on schema modules (`Reservation.last_start_minutes/0`, `MenuItem.services/0`). Both patterns spread the source of truth across files. A per-context constants module gives one canonical home without creating a god module.

**What was rejected:**
1. A single `RestoBookingApp.Constants` god module — would grow into an unstructured dump.
2. Centralising *all* constants regardless of reuse — single-use values are more readable as `@module_attribute` next to where they're used; jumping files to read one line hurts locality.
3. Leaving the `"phone"` / `"email"` kind literals at call sites — initially I wanted to skip these as enum members covered by `kinds/0`, but decided to add named accessors (`Constants.phone/0`, `Constants.email/0`) for symmetry. Pattern matches inside `Contact` itself still use string literals because Elixir can't pattern-match against a function call.

**Implications for implementation:**
- Rule lives in `apps/ELIXIR_RULES.md` (Project guidelines section) as the canonical reference, so both apps inherit it automatically.
- Existing examples to model new modules on: `Reservations.Constants`, `Menu.Constants`, `Contacts.Constants`, top-level `Validations`.
- Counter-examples (intentionally local): `Reservation`'s `@duration_minutes` and `@open_minutes`, `MenuItem`'s `@dietary_tags`.
