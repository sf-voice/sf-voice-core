# core/frontend — sf-voice debugging product

## Read this first

This document is the durable spec for the frontend product. Sibling spec for the API and schema lives at [`../backend/AGENT.md`](../backend/AGENT.md).

**Scope flag.** The repo's top-level `CLAUDE.md` says *"One restaurant only — The Seasons. Not multi-tenant."* That rule applies to the Elixir resto-booking surfaces under `apps/`. It does **not** apply here. `core/frontend` and `core/backend` are a multi-tenant product for sf-voice's external customers.

---

## 1. Product one-liner

sf-voice's debugging tool for voice-AI calls. Customers ingest their call recordings, see exactly what happened on a multitrack timeline, select any slice, propose a fix in plain English, and watch a sandboxed re-run flow back as a PR on their config repo.

The whole product orbits one screen: the timeline view of a single call.

## 2. Audience and posture

- **Audience:** external sf-voice customers running voice agents. Multi-tenant.
- **Mode:** post-mortem only in v1. No live-watch a call as it happens.
- **Posture:** debugging tool, not a dashboard. Optimized for "an engineer just opened a call and something feels off." Density over breathing room. Dark by default. Keyboard-friendly.

## 3. UX inspirations and how we apply them

- **Final Cut Pro / Screen Studio** — multitrack timeline is the centerpiece. J/K/L scrub, in/out markers, snap-to-edits, smooth zoom, solo/mute per track.
- **Vercel** — Geist-clean dev tooling. Log streaming pattern for the reasoning-path panel. Monospace details panes.
- **Sentry** — issue-list density on the call list. Breadcrumbs. Dark mode default. File-to-Linear flow (deferred).
- **code.storage** — clean S3 bucket-input paradigm for the `/settings/buckets` page.

## 4. Top-level routes

| Path | Purpose |
|---|---|
| `/` | Call list. Sentry-style table. Filters: latency, interrupt presence, error, date, caller number, ASR keyword. |
| `/calls/:id` | The timeline view. Primary screen of the product. |
| `/calls/:id/slices/:sliceId` | Selected slice + prompt input + streaming reasoning-path panel + A/B audio player. |
| `/logs` | DAW-style log explorer. Audio tracks on top, synchronized event streams and log list below. See §15. |
| `/settings` | Workspace settings — General tab. Tab strip layout, see §14. |
| `/settings/team` | Members tab. Invite, role, remove. Route already exists (untracked `settings-team.ts`). |
| `/settings/integrations` | Integrations tab. Data sources (AWS, GCP, …) + Notifications (Slack, Discord, Telegram, …) grouped, with search. See §14. |
| `/settings/notifications` | Per-event delivery routing across enabled notification integrations. |
| `/settings/buckets` | S3 bucket input. **Folding into `/settings/integrations` → Data sources → AWS.** Keep the route as a redirect once the integration card lands. |
| `/settings/org` | Config repo URL, Slack webhook URL, notification prefs. Predates the integrations tab; migrate fields into Integrations + General over time. |

## 5. The timeline view

Stacked tracks, top to bottom:

1. Caller waveform
2. Caller VAD probability curve
3. AI waveform
4. ASR partial-text strip (caller side)
5. ASR partial-text strip (AI side, TTS-aligned)
6. LLM event dots (TTFT marker, tool-call start)
7. Tool-call bars (named, with duration)
8. Latency overlays (vertical brackets, e.g. `EOT → first TTS byte = 1.2s`)
9. Interrupt highlight bands (red overlap across caller + AI rows)

Interactions:

- **Space** play / pause.
- **J / K / L** scrub backward / pause / scrub forward.
- **I / O** set in-point / out-point.
- **Drag** on the ruler or any track to select a range.
- **Click** an utterance pill to select it (selection = that pill's `start_ms..end_ms`).
- **S** solo the focused track. **M** mute. (Final Cut convention.)
- Hover any element shows a tooltip with the raw ms timing.
- Selected range opens the right side panel: utterances in range, LLM events in range, latency stats for range, "Insert prompt" button.

Single source of truth for zoom + scroll + selection lives in `components/timeline/Timeline.tsx`; tracks read from props.

## 6. The prompt-on-slice flow

User selects a range, clicks "Insert prompt", types a sentence ("the AI cut the caller off here — try a slower turn-taking style"), submits.

The slice detail route opens with a streaming reasoning path panel:

```
✓ slice captured (0:14.2 → 0:18.7)
✓ context assembled
✓ sandbox provisioned
⠿ regenerating AI response…
⠿ rendering TTS audio…
○ opening PR
○ awaiting review
```

Each step:
- Appears as soon as the backend emits it on the SSE stream `GET /api/jobs/:jobId/events`.
- Posts to the org's Slack webhook (URL from `/settings/org`).
- Updates `prompt_slices.status` server-side (`draft → sandboxed → pr_open`).

When the final step lands, the panel shows:
- A/B audio player (original AI response on the left, regenerated placeholder TTS on the right) with synced scrub.
- Diff of the system prompt that the sandbox used.
- Link to the PR on the customer's config repo (placeholder URL in v1).

**v1 backend stubs the work.** The UI is real, the events are real, the Slack posts are real, the audio is a placeholder TTS file. See `core/backend/AGENT.md` § sandbox-stub job.

## 7. Re-transcribe / re-diarize

Button on the call view. Kicks off a `transcribe` job. Same reasoning-path drawer as the prompt-on-slice flow. On completion, the transcript list re-renders with the new `transcript_runs.id`. Previous runs are kept (versioned in the schema) so the user can switch between transcription versions in the UI.

## 8. Latency / interrupt thresholds

v1 defaults (hardcoded inline in `src/lib/timeline.ts` per CLAUDE.md rule 21 — extract to a constants module only on second use):

- `INTERRUPT_OVERLAP_MS = 200` — AI TTS starts while caller VAD probability > 0.5 for at least this long.
- `SLOW_TURN_MS = 1500` — total turnaround from caller-stops to AI-speaks above this is flagged.
- `DEAD_AIR_MS = 3000` — gap above this with no VAD activity on either side is flagged.

Per-org configurability is deferred to v2.

## 9. Tech stack

- **Runtime:** React 19, rspack 2, Tailwind 4.
- **Helpers:** `cn()` from `src/lib/utils.ts` (clsx + tailwind-merge).
- **Router:** TanStack Router v1 (file-based, typed). Confirmed pending — see open decisions in `~/.claude/plans/squishy-dancing-pearl.md`.
- **Server state:** TanStack Query v5.
- **Audio waveform:** WaveSurfer.js v7 with the regions plugin.
- **Streaming events:** native `EventSource` (SSE).
- **Time formatting:** `date-fns`.

No charting library in v1. The VAD curve renders as a tiny inline SVG; if a third track ever needs it, propose a library before introducing one (CLAUDE.md rule 19).

## 10. Semantic search

The call list page has a search input next to the filters. Typing a phrase ("customers giving up", "wrong booking time confirmed", "AI repeated itself") fires `GET /api/search?q=...`. Results render as utterance hits with the parent call linked; clicking a hit opens the call's timeline scrolled to that utterance.

This is powered by per-utterance embeddings stored in DuckDB. The query string is embedded with the same model and matched via cosine k-NN. See `core/backend/AGENT.md` § 5 for the data layer.

## 11. Out of scope for v1

- Live-watch a call as it happens.
- Customer S3 bucket auth (the input field is UI only; reads come from internal/test buckets).
- Real sandbox spin-up. Real GitHub PR creation against a customer config repo.
- Topic clustering UI (utterance-level embedding search is in; visualising clusters is not).
- Anomaly auto-detection (no "AI flagged this call as suspicious" yet).
- Multi-call dashboards (p50 latency trends, weekly comparisons).
- Annotations / file-to-Linear from a turn.
- Light mode.

---

## Cross-references to the backend

- The reasoning path consumes SSE events from `GET /api/jobs/:jobId/events`. Event shape: `{ step: string, status: "pending"|"running"|"done"|"failed", ts: iso8601, detail?: string }`.
- "Re-transcribe" calls `POST /api/calls/:id/transcribe-runs` → returns `{ job_id }`.
- "Insert prompt" calls `POST /api/calls/:id/slices` with `{ start_ms, end_ms, prompt_text }` → returns `{ slice_id, job_id }`.
- Org settings call `PATCH /api/org` with `{ config_repo_url, slack_webhook_url, bucket_name, bucket_prefix, bucket_region }`.

Full schema and route surface live in [`../backend/AGENT.md`](../backend/AGENT.md).

---

## 12. Layout shell

Sidebar + content area, single-pane shell that every authenticated route renders inside.

### Sidebar anatomy

Fixed-width 256px column, same canvas color as the content area, separated by a single 1px `border-border` on the right. No raised panel, no shadow. Three vertical zones:

1. **Identity zone — top.**
   - Org switcher button: full-width slot, 12px padding, avatar + workspace name + `chevron-down`. Shape language says "menu trigger", not "nav row".
   - Omni-search input directly below it, with a visible `⌘K` shortcut chip on the right (see §13).

2. **Navigation zone — middle.**
   - Nav rows ~36px tall, 12/16 padding, 8px gap.
   - Active row = filled rounded tile (`bg-surface-1`, `radius-md`). No left-border accent.
   - Sections separated by whitespace only. One exception: a "Pinned" header in muted caps (`text-xs uppercase tracking-wider text-muted-foreground`).
   - Nav is data-driven (see §17.5) — `<Sidebar>` reads from `src/lib/nav.ts`, never hard-codes routes.

3. **Status zone — bottom, dock order from top.**
   - Optional alert card (e.g. "Action required") when present.
   - Optional upgrade pill when applicable.
   - User pill, always last: avatar + name + `…` overflow trigger, 36px tall, distinct shape from the org switcher. The user pill is the only entry point to the account menu — **no duplicate avatar in the top-right** (ElevenLabs has both; we don't).

Sidebar collapses to a 56px icon rail via toggle in the content header. Active state, hover state, and badges stay legible at icon size.

### Content header

Single 56px strip across the content area:

- **Left:** sidebar-collapse icon, then breadcrumb (e.g. `Workspace settings ▸ Integrations`).
- **Right:** `Feedback`, `Docs`, `Ask` (ghost buttons, thin border, 32px tall), then `Notifications` bell, then `Theme toggle`.

The header sits on the content's own background; no separator between header and page body — the page provides its own outer padding.

## 13. Search system

Two distinct surfaces, never collapsed into one.

### Omni-search — ⌘K palette

Sidebar-anchored input at the top of the identity zone (just under the org switcher), with a visible `⌘K` shortcut chip on the right. Click or shortcut opens a centered modal palette with mixed sections:

- **Resources** — calls, slices, integrations, log entries matching the query.
- **Commands** — navigate to a page, run an action ("Re-transcribe latest call", "Open log explorer at last error").
- **Recents** — last few visited resources, shown when the input is empty.

Keyboard inside the palette: `↑ ↓` move · `↵` activate · `⌘↵` open in new tab (for resources) · `ESC` close. `/` is reserved as an alias for `⌘K` from any page that isn't already focused on a text input.

### Scoped search

Lives *inside* the content area, scoped to the current resource. Examples:
- Utterance search on a call (already exists, §10).
- Log query bar on the Logs page (§15).
- Integration search on Settings → Integrations (§14).

Scoped search filter state always round-trips through the URL (§17.1).

## 14. Settings

Top-level route `/settings`, tabbed. Tab strip under a single H1 "Workspace settings". Active tab = filled pill + bottom-border accent (ElevenLabs Workspace pattern). Each setting renders as a row: title + one-line description on the left, action button (outlined, leading icon) on the right. Horizontal divider between rows. Rows ~88px tall. Destructive actions live in a "Danger Zone" container at the very bottom of the General tab — red label, heavier border, ghost-style destructive button inside.

### Integrations tab — IA

One tab, two internal groups, **search across both**.

- **Data sources** — AWS S3 (folds in the existing `/settings/buckets` content), GCP Storage, others as they land.
- **Notifications** — Slack, Discord, Telegram, email, webhook.

Each group renders as a grid of integration cards: provider logo, name, one-line state (e.g. "Connected · bucket `sf-voice-prod` / prefix `calls/`"). Card click → right rail with connect/disconnect, config fields, last-sync status.

Search input at the top of the page filters cards across both groups in place; matched cards stay in their group, non-matches dim out (don't reflow). Cards are keyboard-navigable (`↑ ↓ ← →` within the grid).

### Org switcher popover

Triggered from the org switcher button (§12). Contents:

1. Search input at the top.
2. List of orgs the user is **actually a member of** — no global org directory. Each row: avatar, name, role chip.
3. Divider.
4. `Create organization`, `Join organization`, `Workspace settings` (jumps to `/settings`).

## 15. Logs page — DAW-style

Logs is the second primary surface alongside the per-call timeline view (§5). Same metaphor, broader scope: **audio is first-class**, log streams sit synchronized below the audio tracks. Cursor on the audio drives the log list, never the other way around.

### Layout, top-to-bottom

1. **Filter bar** — time range, severity (`info / warn / error`), node, call id, type (`runtime / trace / both`), free-text query. State lives in the URL (§17.1).
2. **Audio tracks** — caller waveform, AI waveform. Always shown. When the visible window contains no call audio (or the cursor sits in a gap between calls), the tracks render empty/dim — the tracks stay, the audio is absent. No fallback UI; the absence is the signal.
3. **Event tracks** — VAD, LLM events, tool calls, runtime severity bands (color-coded `info/warn/error` dots), kubernetes node bands (per-node color strip). Solo/mute per track (`S` / `M`).
4. **Playhead and ruler** — shared across all tracks. `Space` plays from cursor. `J / K / L` scrub.
5. **Log list** — pinned below the tracks, virtualized (§17.3). **Auto-paginates to the cursor's position**: as the cursor moves, the list scrolls so the row whose `ts` is closest to the cursor is in view, highlighted. The list follows the cursor, not the inverse.

### Cursor semantics by zoom level

- **Zoomed in (call-level, e.g. ≤ 5 min visible).** Cursor is an instantaneous playhead, ms-precise. Log list focuses on the single row at the cursor.
- **Zoomed out (e.g. last 24h, last 7d).** Audio collapses to a sparse strip of call clips on the timeline. Cursor becomes a *window selector* — drag to pick a range; the log list paginates to that range.

A zoom indicator in the filter bar makes the current mode explicit. Switching mode is via mouse wheel + `⌥`, pinch, or `+ / -` keys.

### Click-to-scrub

Clicking any log row jumps the cursor to that row's `ts`. The audio doesn't reset, doesn't pause, doesn't dim — it scrubs. If the row has no associated audio (runtime line from a pod outside any call window), the cursor still moves; the audio tracks render empty at that timestamp.

### Right-rail detail

A row click *also* opens a right rail for deep inspection of that single event: full structured fields, related events, raw payload, tool I/O for trace rows. The rail is for inspection only — the main surface stays the timeline. The rail is the **only** place row-level detail appears; rows themselves stay scannable.

### What "instruction logs" includes

Both runtime and trace, in one stream, with a leading type icon on each row:

- **Runtime** — `info / warn / error` from our k8s pods (line, severity, node, pod, message).
- **Trace** — per-call LLM/tool events (system prompt, tool invocation, retry, response). Trace rows can expand inline to show one level of the tree; full tree lives in the right rail.

Default filter: type = both. The filter chip lets users narrow to runtime-only or trace-only.

## 16. Design tokens

Single source of truth. Defined in `src/index.css` via Tailwind v4 `@theme`. Components reference token names; **no raw hex or oklch values in component files.**

### Color tokens

Build on the existing palette; add these where missing:

- `--color-background` — canvas.
- `--color-surface-1` — elevated cards, modal bodies, active sidebar tile. One notch lighter than canvas.
- `--color-surface-2` — popovers, right-rail panel, log row hover.
- `--color-border` — default 1px border. Use full opacity for prominent dividers (sidebar↔content). Use `/60` for subtle row dividers and card outlines.
- `--color-danger`, `--color-warn`, `--color-info`, `--color-success` — severity palette for logs and status.

Current state: most surfaces use `bg-background`, which is why the Connect AWS modal felt flat against the timeline (today's bug). Migrate cards / modals / right-rail to `bg-surface-1` / `bg-surface-2` opportunistically as we touch them — no big-bang refactor.

### Spacing

Multiples of 4: `4 / 8 / 12 / 16 / 24 / 32 / 40`. Outer page padding `32–40`. Card padding `16–20`. Row vertical padding `16`. Sidebar↔content gap = `0` (just the border); content provides its own outer padding.

### Radius

- `radius-sm` `4` — chips, severity dots.
- `radius-md` `8` — nav rows, buttons, inputs.
- `radius-lg` `12` — cards.
- `radius-xl` `16` — modals, large cards.

### Borders

Single border token used everywhere: sidebar↔content divider, tab underlines, card outlines, row dividers in settings, danger-zone container. **Never combine shadow + border on the same element** — pick one.

## 17. Codebase architecture conventions

In order of leverage. Apply opportunistically when touching a file; no big-bang refactors.

### 17.1 URL is the source of truth for filters

Every filter on every page round-trips through TanStack Router search params. Time range, severity, node, query, sort, view mode — all in the URL. Shareable, bookmarkable, back-button works. Especially load-bearing for Logs and the call list. Painful to retrofit later.

### 17.2 Streaming model = SSE

SSE is the channel for live data (log tails, in-progress call traces, the reasoning-path stream we already have). One canonical `useEventStream(url)` hook, built on native `EventSource`. No WebSockets in v1.

### 17.3 Virtualize lists from the start

`@tanstack/react-virtual` for the log timeline, call list, members list, integration grid. Add it the first time a list could plausibly exceed 200 rows — not when it breaks.

### 17.4 Global keyboard registry

Define shortcuts in one place: `src/lib/shortcuts.ts`. Conventions:

- `/` focus scoped search · `⌘K` open omni-palette
- `J / K / L` scrub on timeline pages · `J / K` row navigation on lists
- `↵` activate · `ESC` close rail / modal
- `G then L` go to Logs · `G then C` go to Calls · `G then S` go to Settings
- `S / M` solo / mute focused track (Final Cut convention, already in §5)

Single `useShortcuts()` hook reads from the registry. Features don't invent their own bindings without registering.

### 17.5 Sidebar nav is data, not JSX

`src/lib/nav.ts` exports an array of `{ id, label, icon, to, section?, badge? }`. `<Sidebar>` reads from it. Adding a tab = appending an entry.

### 17.6 Three-tier component layering

- `src/components/ui/` — primitives (Button, Input, Popover, Dialog, Tabs, Tooltip, Avatar). No domain logic.
- `src/components/patterns/` — generic compositions (SettingRow, StateContainer, RightRail, FilterChip, EmptyState, IntegrationCard).
- `src/components/features/` — domain-specific (LogRow, OrgSwitcher, CallWaveform, TimelineTrack).

Today most things are flat in `components/` with a few subfolders. Re-bucket on touch; don't move untouched files.

### 17.7 `<StateContainer>` pattern

One component wraps `{ isLoading, error, data, empty? }` and renders the right state with a consistent visual language. Routes stop hand-rolling loading/error/empty per page. The existing `components/empty/` is the seed — generalize it into `patterns/`.

### 17.8 Typography components

`<H1>`, `<H2>`, `<H3>`, `<Body>`, `<Caption>`, `<Mono>`. Pages don't write raw `text-3xl tracking-tight font-display`. The Playfair display + Inter body + mono stack is baked into these.

### 17.9 Route folders, not flat files

Move from `routes/calls-index.tsx`, `call-detail.tsx`, `slice-detail.tsx` to `routes/calls/index.tsx`, `$callId.tsx`, `$callId.slices.$sliceId.tsx`. Settings: `routes/settings/{index,team,integrations,notifications}.tsx`. TanStack Router file-based nesting. Apply when adding new routes; migrate existing ones on touch.

### 17.10 Data layer split when it grows

`src/lib/queries.ts` is fine until it exceeds ~400 lines or has >8 resources. Then split per-resource: `lib/queries/calls.ts`, `lib/queries/logs.ts`, sharing `lib/api.ts` client. No premature split.

### 17.11 Icon set

Pick one (Lucide or Phosphor) and stick to it. Tree-shakeable named imports. No raw SVG drops inside feature components — if a glyph is missing, add it to one shared `components/ui/icons.tsx` source.

### What we are *not* adding

- **Storybook.** Premature for current team size. A `/dev` route rendering all primitives is the cheap equivalent.
- **CSS-in-JS** (vanilla-extract, stitches). Tailwind v4 + tokens is enough.
- **State library** (Zustand, Jotai). TanStack Query + URL covers ~90%; defer until proven need.
