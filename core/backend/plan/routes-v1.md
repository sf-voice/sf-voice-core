# Routes (v1)

| Method + Path | Purpose |
|---|---|
| `GET /api/calls` | List calls for the resolved org, paged, with filter query params |
| `GET /api/calls/:id` | Call detail (the row, with active `transcript_runs.id`) |
| `GET /api/calls/:id/transcripts` | Per-utterance rows for the active transcription run, sorted by `start_ms` |
| `POST /api/calls/:id/slices` | Create a `prompt_slices` row + enqueue `sandbox` job → `{ slice_id, job_id }` |
| `POST /api/calls/:id/transcribe-runs` | Enqueue a `transcribe` job → `{ job_id }` |
| `GET /api/slices/:id` | Slice detail (range, prompt, status, pr_url) |
| `GET /api/jobs/:id` | Job row including `progress_steps` |
| `GET /api/jobs/:id/events` | SSE stream: replay `progress_steps` on connect, then tail new step events |
| `GET /api/search?q=...&limit=N` | Semantic search across `transcript_embeddings` → list of `{ transcript_id, call_id, text, dist }` joined back to `transcripts` + `calls` for surface metadata |
| `GET /api/org` | The resolved org row |
| `PATCH /api/org` | Update `config_repo_url`, `slack_webhook_url`, bucket fields |

Auth in v1: a fixed `org_id` from env. Real auth (per-customer sessions) is v2.
