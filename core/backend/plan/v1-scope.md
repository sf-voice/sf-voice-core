# v1 scope

- Schema for `orgs`, `calls`, `files`, `transcripts`, `transcript_runs`, `jobs`, `prompt_slices`, `users`, `org_users`, `sessions`, `auth_identities`, `invites`, `documents` (MySQL, source of truth in `core/backend/entities/`) and `transcript_embeddings` (DuckDB).
- **Ingest job:** list S3 prefix → upsert `files` rows → for each new audio file, create or update a `calls` row → enqueue a `transcribe` job.
- **Transcribe job:** pull audio from S3 → call end-of-turn VAD service for segment boundaries → call Whisper per segment → call diarization → merge into utterances → write `transcript_runs` + per-utterance `transcripts` rows → embed each utterance via OpenAI → upsert into DuckDB `transcript_embeddings`.
- **Slice + prompt API:** create `prompt_slices` row → enqueue stub `sandbox` job that emits the seven canonical step events (and posts each to the org's Slack webhook) → set `prompt_slices.status` to `pr_open` with a placeholder URL when done.
- **Read APIs** for the timeline view: list calls; get call detail with utterances; get a job and tail its events via SSE.
- **Semantic search API:** `GET /api/search?q=...` runs the query string through the same embedding model, does nearest-neighbour against DuckDB, joins back to MySQL `transcripts` for the rows.

**Out of scope:** real sandbox provisioning, real PR creation, ClickHouse wiring, customer-bucket auth, multi-model embedding A/B.
