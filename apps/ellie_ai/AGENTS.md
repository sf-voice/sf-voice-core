# EllieAi — agent rules

App-specific rules for `apps/ellie_ai`. Read after the repo-root `AGENTS.md`.

**Stack rules:** Phoenix/Elixir conventions live in [`../ELIXIR_RULES.md`](../ELIXIR_RULES.md). Read both files before working in this app.

**Decisions:** [`MEMORY.md`](MEMORY.md) holds every architectural decision affecting this app. Read it first.

---

## Scope

Ellie is the voice-AI orchestrator for restaurant phone calls. It owns:

- Telnyx integration (media streaming, call control, webhooks).
- OpenAI Realtime WS (ASR + LLM + TTS in one pipe).
- Per-call supervision tree (CallServer + AudioBridge + VadGate + Archivist).
- Local Silero VAD for end-of-turn detection.
- Audio archival to S3 (per-turn + composed).
- All staff UI (`/customers`, `/customers/:id`, `/calls/:id`, `/settings`).
- A `customer_summary` read-model populated by polling resto.

Ellie **never receives writes from resto**. Ellie is the actor; resto only exposes read endpoints. See `MEMORY.md` (2026-05-09).

Multi-tenancy: ellie has `groups` (UX-only grouping for staff across locations) and `orgs` (the per-restaurant unit). Every per-call concept carries `org_id`.

---

## Design rules (enforced in code review)

Ellie runs on screens inside restaurants — bright sun, dim service light, smudged glass. Design for legibility. The rules below are the floor, not the target.

### Contrast

- Every text/background pair must clear **WCAG AAA**: contrast ratio **≥ 7:1** for body text, **≥ 4.5:1** for large text (18pt+ or 14pt+ bold).
- No grey-on-grey, no muted timestamps, no low-contrast decorative borders. If a divider isn't visible against its background at arm's length under fluorescent light, it shouldn't be there.

### Typography

- Minimum font size **14px** for anything the user has to read to act.
- Minimum font weight **500** for body copy. No `font-thin`, `font-extralight`, or `font-light` classes anywhere.
- Placeholder text must meet the same contrast floor as body text. If it can't, drop the placeholder and use a persistent label instead.

### State and feedback

- Disabled, hover, focus, and active states must each independently meet the contrast floor. A disabled button that fades to invisible is a bug.
- Focus rings must be visible without squinting — solid, ≥ 2px, and high-contrast against both the element and its background.

When a design or component conflicts with these rules, fix the design. Do not silently relax the rule.

### Clickable rows

Tables and lists where the row navigates somewhere: the **whole row is the click target**. Never put navigation behind a trailing "Open →" link. Use a full-row `<.link>`, or an absolute-inset overlay when there's a nested button to keep working.

---

## Per-call state lives in `EllieAi.Calls.Memory`

Don't thread `org` / `org_id` / per-call metadata through function arguments during a call. Read it from `EllieAi.Calls.Memory` at the point of use.

Per-call modules (`AudioBridge`, `VadGate`, `Archivist`, tool implementations) must **not** `alias EllieAi.Orgs.Org`. The org is data carried in the call's Memory; not a typed argument the call modules know about.

This keeps the call tree's supervision boundary clean: a process that crashes and respawns reads fresh state from `Memory` rather than relying on an arg that the supervisor doesn't carry.
