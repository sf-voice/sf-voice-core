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

---

## 2026-05-07 — Architectural rule: ellie owns all Telnyx, resto owns reservations only

**What was decided:** `resto_booking_app` is purely a reservation system with customer records. `ellie_ai` owns ALL Telnyx communication. Resto never speaks to Telnyx, never receives Telnyx webhooks, never holds Telnyx credentials.

**Why:** Clean separation of concerns. resto = system of records (slow-changing customers + reservations). ellie = agentic primitives (fast-changing calls, transcripts, tool calls). Each app's responsibilities, deps, env, and failure modes are independently understandable.

**What was rejected:** Earlier draft had resto handling Telnyx failover webhooks. Removed.

**Implications for implementation:**
- resto's `mix.exs` has zero Telnyx-related deps.
- resto's container env is minimal: `INTERNAL_API_TOKEN` only.
- All HTTP between the apps is bearer-authed with `INTERNAL_API_TOKEN`.

---

## 2026-05-07 — Voice AI built from scratch (deliberate non-cost-optimal choice)

**What was decided:** Build `ellie_ai` as a custom voice orchestrator (Telnyx Media Streaming + OpenAI Realtime + custom Silero VAD + custom audio archival). Reject managed alternatives (Vapi, Retell, Bland.ai, Telnyx AI Assistants).

**Why:** Outside-voice flag during /plan-eng-review noted that for one restaurant with <50 calls/day, ~3-4 weeks of build is more than 100x the cost of a managed agent. The user explicitly chose to own the stack for control + learning, not for cost optimization.

**What was rejected:** Managed agent path (3-4 days vs 3-4 weeks). Acknowledged as faster but loses local VAD, audio archival, and control over turn boundaries.

**Implications for implementation:**
- This is a learning + control investment, not a cost-optimal one. Don't second-guess it under pressure.
- If v1 hits real production friction (latency / reliability / cost), spike Vapi/Retell as the v1.1 escape hatch (TODOS.md #6).

---

## 2026-05-07 — All staff UI lives on ellie_ai; resto only renders /floor_plan

**What was decided:** ellie_ai hosts every staff page (`/customers`, `/customers/:id`, `/calls/:id`, `/settings`). resto_booking_app only renders the existing `/floor_plan` for guest bookings.

**Why:** Single subdomain for staff workflow. No cross-domain navigation when an escalation happens. resto can stay focused as a system of records.

**What was rejected:** Original split where `/customers*` was on resto and `/calls/:id` was on ellie. Reversed by user during /plan-eng-review for staff-workflow simplicity.

**Implications for implementation:**
- ellie_ai gains a `customer_summary` read-model table populated by polling resto's `GET /api/customers` endpoint.
- resto exposes read endpoints only; never reaches out to ellie.
- Nightly reconciliation cron in ellie reads from resto.

---

## 2026-05-09 — ellie polls resto; resto never calls ellie (reversal)

**What was decided:** All data flow between resto and ellie is initiated by ellie. resto exposes its `/api/...` endpoints and that's it. ellie is responsible for writing the http client to resto and for the polling cadence (real-time during a call via tool calls, plus a nightly reconciliation cron for the `customer_summary` read-model).

**Why:** Keeps resto's responsibility narrow (system of records). One direction of traffic is simpler to reason about, secure, and operate. resto stays oblivious to whether ellie is up, down, blue, or green. No retry/backoff/circuit-breaker logic on the resto side.

**What was rejected:** Earlier plan-eng-review decision (2B.C in /plan-eng-review notes) that resto pushes customer-events webhooks to ellie. Removed: `RestoBookingApp.EllieClient`, `:req` dep from resto's mix.exs, `Customers.broadcast_after/2` private function. The `customer_summary` read-model in ellie still exists; it's now populated by polling rather than by webhook.

**Implications for implementation:**
- resto: no outbound HTTP, no `EllieClient`, no `:req` dep.
- ellie: owns `EllieAi.RestoClient` (or similar). Hits `GET /api/customers`, `GET /api/customers/:id`, etc. Reconciliation cron lives in ellie.
- Real-time customer lookups during a call: ellie's tool implementation calls resto directly per turn; no event delivery semantics to worry about.

---

## 2026-05-09 — ellie's customer lookup waterfall (local → resto → ask)

**What was decided:** When a call arrives, ellie resolves the caller's identity in three ordered steps:
1. **Local read** — `customer_summary.tel = <caller_e164>` in ellie's own DB. Hit → done.
2. **Resto fallback** — `GET /api/customers/by_tel/<e164>` on miss. Hit → upsert into ellie's `customer_summary`, proceed.
3. **Ask on call** — total miss → AI asks for the caller's name on-call. Once answered, ellie `POST /api/customers` to resto (E.164 + name), reads back the resto-issued id, caches to `customer_summary`.

**Why:** Three properties at once. (1) Sub-millisecond happy path for repeat callers — no network round-trip during the most common case. (2) resto stays the system of records — every new customer is born in resto, ellie's summary is always a derived cache. (3) Graceful unknown-caller flow — the AI handles the introduction naturally rather than failing or fabricating.

**What was rejected:**
- Always-poll-resto-first (skips the local cache benefit).
- Write-to-ellie-first-then-async-sync-to-resto (violates "resto = source of records" and risks split brain if the sync fails).
- Reject unknown callers (terrible UX for a restaurant booking line).

**Implications for implementation:**
- resto exposes `GET /api/customers/by_tel/:tel` and `POST /api/customers`. Both bearer-authed (`INTERNAL_API_TOKEN`).
- ellie's `lookup_customer` tool implements the waterfall. Tool returns `{found: true, customer: {...}}` or `{found: false}`. The "ask" step is the AI's natural follow-up to a `found: false` response, not a separate tool.
- Nightly reconciliation cron (already planned) keeps `customer_summary` from drifting on the slow-changing fields (name corrections, email added on the website later).
- resto's `Customers.upsert_by_tel/2` is the right server-side handler for `POST /api/customers` — naturally idempotent if ellie retries.

---

## 2026-05-09 — ellie has its own visual theme, deliberately different from resto

**What was decided:** ellie's `assets/css/app.css` defines a separate "light clinical" theme distinct from resto's "classical restaurant" bronze/sage. ellie palette: ivory ground (`oklch(98% 0.003 80)`), charcoal text (`oklch(20% 0.02 60)`), single muted teal accent (`oklch(58% 0.08 200)`). Body font Inter (shared with resto). Mono font IBM Plex Mono 13px for tool names, system events, timestamps, durations.

**Why:** Different audience, different needs. resto is for guests booking — must feel like the restaurant. ellie is for staff operating the AI — must feel like an ops console. Same body font (Inter) keeps the products feel like siblings; different palettes signal "this is a different kind of surface."

**What was rejected:** Shared theme, dark ops console (option A in 5B), mid-century technical (option C in 5B).

**Implications for implementation:**
- Do NOT import resto's app.css into ellie. Each defines its own theme block.
- New components introduced for ellie (sentiment dot, listen button states, tool replay card) live in ellie's CSS only.
- Sentiment colors (sage / warm-gray / red) are independent of the muted teal accent so they don't clash.
- Dark mode for ellie deferred to v1.1 (TODOS.md #8).

---

## 2026-05-09 — Multi-tenancy: ellie has groups + orgs; resto has orgs only (reverses earlier "single tenant only" decision)

**What was decided:** The system supports multiple restaurants. Resto becomes multi-tenant within one deploy (one resto instance hosts multiple `orgs`, each scoped by `org_id`). Ellie has both `groups` (a UX-only grouping for staff: "show me all calls across both Seasons locations") and `orgs` (the per-restaurant unit). Each org on ellie carries its own `telnyx_phone_number`, `resto_base_url`, `internal_api_token`, voice settings, system prompt.

Customers are isolated per org. Same person calling Seasons SF and Seasons LA is two separate customer records — Mary at SF is not Mary at LA.

**Why:** The user wants to support multiple restaurants. "The Seasons Restaurant Group" with two locations was the concrete trigger. Customer relationships are per-restaurant (Mary may be a regular at one location and unknown at another), so isolation is required. One resto deploy serving multiple orgs (rather than N deploys of single-tenant resto) keeps ops cost flat instead of linear.

**What was rejected:**
- Earlier locked decision (2026-05-07): "single tenant, The Seasons only, no multi-tenancy in v1." Reversed by user 2026-05-09.
- Pure A1 (one resto deploy per restaurant): rejected for ops cost.
- Hybrid C (resto as a library bundled with ellie per deploy): rejected for not matching the working two-service architecture.

**Implications for implementation:**
- Resto: add `orgs` table; every domain table (`customers`, `contacts`, `reservations`, `tables`, `menu_items`) gains `org_id`. Tables and menu move from static modules to DB rows scoped by org. Routes become path-scoped: `/api/orgs/:org_slug/...`. The floor plan UI moves from `/` to `/:org_slug/floor_plan`.
- Ellie: add `groups`, `orgs`, plus `org_id` on `customer_summary` (unique index becomes `(org_id, phone_e164)`). All tool calls carry `org_id` in their context. Lookup waterfall is `(org_id, phone)`-keyed.
- Auth: single shared `INTERNAL_API_TOKEN` across all orgs. Org is data carried in the path; not authentication.
- Both demo orgs seeded out of the box: "Seasons SF" and "Seasons LA" with distinct names + locations.

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

---

## 2026-05-09 — Voice cloning is out of v1; Realtime preset voices only

**What was decided:** v1 ships with OpenAI Realtime's preset voices (`alloy`, `echo`, `shimmer`, etc.), configurable per-org via the `voice` setting. Voice cloning (ElevenLabs / Cartesia / equivalent) is parked for v1.1 or later.

**Why:** Cloning requires a different pipeline than Realtime — the unified Realtime WS handles ASR + LLM + TTS in one round-trip. Cloning means splitting that into ASR → LLM → TTS, adding ~400-700ms of first-byte latency per turn. v1's goal is a conversational feel; the preset voices clear that bar without burning the latency budget. Revisit when we know the demo's tolerance for the slower split pipeline.

**Implications for implementation:**
- The `voice` setting maps directly to OpenAI Realtime's `voice` parameter.
- No separate TTS service plumbing; no ElevenLabs credentials required.
- v1.1 spike captured in TODOS.md.

---

## 2026-05-09 — Voice UX commitments (v1)

**What was decided:** Locked the live-call UX behavior:
- **Greeting time-to-first-word:** AI speaks within ~1s of call connect.
- **Barge-in:** caller can interrupt the AI mid-sentence; AI mutes < 50ms via state flag + `response.cancel` + `response.id` filtering on in-flight audio frames. **In v1 scope.**
- **Backchanneling:** "mm-hmm" / "got it" — driven by system prompt directive only; not user-configurable.
- **Silent caller:** AI does NOT auto-hang up. Stays on the line. Hangup is tool-driven only (`hangup_call` tool fires when the AI hears a closing phrase like "thanks, that's all" or "goodbye").
- **Escalation to staff:** verbal handoff ("Let me get a human on the line for you") then 3-way muted conference. AI stays in the audio path for transcription only; sends `response.cancel` after each detected end-of-turn so it never speaks during the human portion.
- **Recording disclosure:** **NOT** announced verbally during the call. Covered in Terms of Service instead. Caller's consent is implicit when they call the published number.

**Why:** Restaurant phone calls feel formal and corporate when the AI announces "this call is being recorded." TOS captures the legal disclosure without disrupting the flow.

**Implications for implementation:**
- TOS page on resto must explicitly state calls are recorded and transcribed when the caller phones the published number.
- AudioBridge mute is a flag check on every outbound frame; OpenAI cancellation handles the model side; in-flight audio frames whose `response.id` is the cancelled one get dropped.
- `hangup_call` is a Tool implementing `EllieAi.Tools.Tool`. AI uses it via Realtime function-calling.

---

## 2026-05-09 — Per-call supervision tree + audio threading

**What was decided:** Each active call spawns a `CallTree` Supervisor (strategy `:rest_for_one`) under a top-level `DynamicSupervisor`, holding four GenServers: `CallServer` (orchestrator), `AudioBridge` (Telnyx WS + OpenAI WS, fan-out), `VadGate` (Silero ONNX, end-of-turn detection), `Archivist` (audio buffer + S3 multipart upload). Tools execute via `Task.async_nolink` from CallServer — no separate ToolDispatcher process.

The CallTree is keyed in a Registry by Telnyx's durable `call_control_id` so the WebSocket can reconnect and re-bind to the same tree.

**Why:** `:rest_for_one` means an AudioBridge crash brings VadGate + Archivist with it (they all share the audio stream); an Archivist crash leaves AudioBridge + VadGate alone (we lose archival for one segment, not the call). Splitting workers means audio keeps flowing when one of them stalls (Silero inference, S3 upload). Tools as `Task.async_nolink` keeps the supervision tree minimal.

**Implications for implementation:**
- One Registry: `EllieAi.CallRegistry`, `via: {EllieAi.CallRegistry, call_control_id}`.
- AudioBridge fan-out is `GenServer.cast/2` per audio frame — non-blocking.
- Outbound mute is a flag in AudioBridge state; on `{:turn, :speech_start}` from VadGate, AudioBridge sets `:muted` + sends `response.cancel` + `input_audio_buffer.clear` to OpenAI.
- Audio frames are filtered by `response.id` against the current tracked one; in-flight frames from cancelled responses are dropped.

---

## 2026-05-09 — Audio archival: per-turn + composed full.wav, S3 with env-prefixed paths

**What was decided:** Two archival paths run simultaneously per call.
- **Per turn:** at every `:turn :speech_end` from VadGate, Archivist closes the current turn buffer, writes `/tmp/calls/<call_id>/turn-<n>.wav`, uploads to S3 at `<env>/calls/<call_id>/turn-<n>.wav`, persists a `transcript_turns` row referencing the s3 key.
- **Composed:** the same μ-law bytes are appended to a single `/tmp/calls/<call_id>/full.raw`. On call end, converted to `full.wav` and uploaded to `<env>/calls/<call_id>/full.wav`. The `calls` row gets the s3 key.

Both audio assets are referenced in the DB. Same S3 bucket (`sf-voice-demo-calls`). Path prefix is `dev/` for local development and `prod/` for production.

**Why:** Per-turn audio is the natural unit for staff to listen to a specific exchange ("play that turn where Mary asked about allergies"). Full call recording is the unit for compliance and dispute resolution. Same bucket keeps lifecycle policies simple; env-prefix avoids local/prod mixing without separate buckets.

**Implications for implementation:**
- Archivist runs S3 upload as background Tasks so a slow upload doesn't block the audio thread.
- `transcript_turns.audio_s3_key` is nullable until upload completes; UI shows "audio pending" if missing.
- `calls.audio_s3_key` set at finalize time.
- Failed uploads are retried via backoff Tasks for up to 24h; row stays flagged `pending_upload: true`.

---

## 2026-05-09 — System prompts: per-org, EEx-templated, versioned

**What was decided:** Each org has its own system prompt stored in a `prompts` table (per-org, versioned, with `active: true` flag for the current one). Body is EEx-templated; rendered at call start with three classes of substitution:

1. **Static org context:** `<%= @org.name %>`, `<%= @org.location %>`, `<%= @org.time_zone %>`.
2. **Dynamic date facts:** pre-rendered table covering today, tomorrow, this/next week, this/next Friday/Saturday, two-weeks-out, one-month-out (~12 lines). Reduces "next Friday" hallucinations.
3. **Caller context:** when `lookup_customer` hits, recent calls (N=3-5 summarized to 1-2 sentences each) plus identity (name, total visits, notes) are rendered into the prompt. First-time callers get "First-time caller. Greet them warmly and ask their name."

**Why:** Restaurants tweak the AI's persona per location; templating is the safest way to keep a clean separation between operator-editable prose and engineer-controlled structure. EEx is already in the BEAM (no new dep). Versioning lets staff roll back if a new prompt produces bad calls.

**Implications for implementation:**
- `prompts` table: `id, org_id, name, body, version, active, created_by, inserted_at`.
- `EllieAi.Prompts.render_for_call/2` builds the assigns and runs EEx.
- `/settings` UI has a textarea + "Preview against today" button showing the template + rendered output side by side.
- Beyond date facts, AI also has a `current_datetime` tool for mid-call rechecks.

---

## 2026-05-09 — Post-call summary: async, two summaries, gpt-4o-mini

**What was decided:** Telnyx `call.hangup` triggers a `Task.Supervisor` job that summarizes the call via `gpt-4o-mini` and updates the `calls` row with: `summary` (2-3 sentence prose for staff UI), `summary_for_prompt` (1 sentence terse for future caller-context blocks), `outcome` (enum: `booked|modified|cancelled|escalated_resolved|escalated_unresolved|no_action`), `sentiment_score` (EMA of per-turn scores, frozen at handoff if escalated), `tags` (array). Sentiment EMA is computed live during the call via per-turn `gpt-4o-mini` scoring; the post-call job doesn't recompute.

Summaries cover the WHOLE call including the human-to-human portion after escalation. Speaker labels during the human portion are unreliable (no diarization in v1) — turns there are tagged `role: "human"` (singular) and the summary prompt is told both voices may be present.

**Why:** Async keeps call shutdown fast. `gpt-4o-mini` is cheap (~$0.001/call) and accurate enough at 2-3 sentence prose. Two summaries because the staff UI wants prose; future prompts want terseness. Outcome enum makes filterable analytics trivial.

**Implications for implementation:**
- `Task.Supervisor` named `EllieAi.TaskSupervisor` in the supervision tree.
- Failed summary jobs flag the row `summary_pending: true` and retry on backoff for up to 24h.
- `transcript_turns` table has a `phase` enum: `ai_handling | escalation_pending | human_handling | post_resolution`.
- Diarization upgrade (gpt-4o-mini "who said what" pass) deferred to v1.1.
- Real diarization via Deepgram/AssemblyAI deferred to v2.

---

## 2026-05-09 — Per-turn transcripts: eager-persist + PubSub for live UI

**What was decided:** Each turn writes one row in `transcript_turns` per role: `id, call_id, turn_index, role (caller|assistant|human), text, sentiment_score, started_at, ended_at, audio_s3_key, phase`. CallServer is the single owner of the table; AudioBridge/Archivist/VadGate send messages to it. Rows are eagerly persisted as fields arrive (insert on first signal, updates as more pieces land). PubSub broadcasts on `"call:<call_id>"` drive the live `/calls/:id` view.

**Why:** Eager persistence + PubSub means staff see the transcript stream into the UI live, before the call ends. The UX win outweighs the ~3 vs 1 DB writes per turn (still trivial at SQLite scale).

**Implications for implementation:**
- CallServer state holds a `partial_turns` map keyed by `turn_index`; rows are inserted on first signal and `Repo.update/1`'d as later signals arrive.
- Transcripts come from OpenAI Realtime events: `conversation.item.input_audio_transcription.completed` (caller) and `response.audio_transcript.done` (assistant).
- Per-turn sentiment is fired via `Task.async_nolink` against `gpt-4o-mini`; lands as a later message and patches the row.
- The `phase` column lets summaries and the staff UI distinguish AI-handled portions from escalation.

---

## 2026-05-10 — Shared constants live in per-context `Constants` modules

**What was decided:** When a literal value (domain enum, magic number with business meaning, regex, etc.) is used in two or more modules, it gets extracted to a per-context `Constants` module — `RestoBookingApp.Reservations.Constants`, `RestoBookingApp.Menu.Constants`, `RestoBookingApp.Contacts.Constants`. Cross-context shared values go in a top-level `RestoBookingApp.Validations` module. Values used in only one module stay as `@module_attribute` co-located with the function that uses them. Don't preemptively centralise — wait for the second use.

**Why:** The codebase had genuine duplication (`@e164_regex` and `@email_regex` defined identically in `Bookings` and `Contacts.Contact`) and shared values exposed via ad-hoc accessors on schema modules (`Reservation.last_start_minutes/0`, `MenuItem.services/0`). Both patterns spread the source of truth across files. A per-context constants module gives one canonical home without creating a god module.

**What was rejected:** (1) A single `RestoBookingApp.Constants` god module — would grow into an unstructured dump. (2) Centralising *all* constants regardless of reuse — single-use values are more readable as `@module_attribute` next to where they're used; jumping files to read one line hurts locality. (3) Leaving the `"phone"` / `"email"` kind literals at call sites — initially I wanted to skip these as enum members covered by `kinds/0`, but decided to add named accessors (`Constants.phone/0`, `Constants.email/0`) for symmetry. Pattern matches inside `Contact` itself still use string literals because Elixir can't pattern-match against a function call.

**Implications for implementation:**
- Rule lives in both `CLAUDE.md` (as #21) and `AGENTS.md` (under "Project guidelines"). Elixir-specific so it stays project-local, not in global `~/.claude/CLAUDE.md`.
- Existing examples to model new modules on: `Reservations.Constants`, `Menu.Constants`, `Contacts.Constants`, top-level `Validations`.
- Counter-examples (intentionally local): `Reservation`'s `@duration_minutes` and `@open_minutes`, `MenuItem`'s `@dietary_tags`.

