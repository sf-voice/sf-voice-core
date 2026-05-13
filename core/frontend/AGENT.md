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
| `/settings/buckets` | S3 bucket input (wired but unused in v1; auth deferred). |
| `/settings/org` | Config repo URL, Slack webhook URL, notification prefs. |

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
