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

`EllieAi.Calls.Memory` is the in-memory state for a live call. It holds two kinds of shared call-scoped state — nothing else.

### What Memory holds

1. **Immutable per-call entities** (org, user, call config). Loaded at entity call sites under `/entity` and handed to `CallTree`, which writes the ETS row once on bootstrap. Mirrored into the process dict so workers read them via `Memory.org/0` and friends as constant-time dict reads. `Memory.async/1` propagates the dict into spawned tasks.

2. **Append-only live state** (transcript turns, event log). Grown **one finalized turn at a time** via `Memory.append_*` functions during the live call. ETS only — not mirrored into the dict. Readers always see a consistent prefix; nothing is rewritten in place.

### What Memory does NOT hold

- **No database I/O.** Memory is a cache, not a repository. DB fetches happen at `/entity` call sites; results are handed to `CallTree`. `Repo.*` inside `Memory` or a per-call worker is a layering violation.
- **No interim / partial ASR.** In-progress transcription lives in the worker that owns the ASR session (typically `AudioBridge`) and is discarded when the turn finalizes. Only finalized turns are appended.
- **No per-worker private state.** File handles, Silero VAD state, audio frame counters, sequence numbers, in-progress ASR buffers — those stay in the worker's `GenServer` state.

### Per-call workers

Per-call workers (`AudioBridge`, `VadGate`, `Archivist`, `Escalator`, `Sentiment`) MUST NOT accept `%Org{}`, `org_id`, `%User{}`, or any other per-call entity as a function argument. Read entities from `Memory.org/0` and friends — populated by `bootstrap_from/1` on init, or by `Memory.async/1` for spawned tasks.

Per-call worker modules MUST NOT `alias EllieAi.Orgs.Org` (or any other entity module). Aliasing implies pattern-matching or constructing the struct, both of which bypass Memory. Read fields off `Memory.org/0` instead.

The supervision boundary depends on this: a process that crashes and respawns reads fresh state from Memory rather than relying on an arg the supervisor doesn't carry.

### Tools

Tools follow the `EllieAi.Tools.Tool` behaviour and accept `%Org{}` via the **context map** — not through Memory. Tools may run outside a live-call process tree (eval, replay, synchronous invocation) where Memory isn't populated.

Even so:

- Tool files MUST NOT `alias EllieAi.Orgs.Org`.
- Tool files MUST NOT pattern-match `%Org{...} = context.org`.
- Read fields off `context.org` directly: `context.org.id`, `context.org.time_zone`, etc.

The alias-ban is a forcing function for "fields only, never struct shape" — if the `Org` schema gains or loses a field, tools that only read named fields keep working.

----

# Code Conventions 

- Avoid `alias EllieAI.Telnyx.Client` pattern, do `alias EllieAI.Telnyx.Client as TC` instead - less code is better code
