# Cross-references to the frontend

The frontend product spec lives at [`../../frontend/AGENTS.md`](../../frontend/AGENTS.md). Notable contract points the frontend depends on:

- SSE event payload from `GET /api/jobs/:id/events`: `{ step: string, status: "pending"|"running"|"done"|"failed", ts: iso8601, detail?: string }`.
- `progress_steps` is the same shape stored as JSON on `jobs`.
- The sandbox-stub job emits a fixed list of seven steps in order: `slice captured` → `context assembled` → `sandbox provisioned` → `regenerating AI response` → `rendering TTS audio` → `opening PR` → `awaiting review`.
- `prompt_slices.status` transitions `draft → sandboxed → pr_open` over the course of the sandbox job; the placeholder PR URL pattern is `https://github.com/sf-voice/cfg-<org.slug>/pull/0`.
