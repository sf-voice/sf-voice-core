# core/backend — sf-voice debugging API

## Read this first

**Scope flag.** The repo's top-level `CLAUDE.md` says *"One restaurant only — The Seasons. Not multi-tenant."* That rule applies to the Elixir resto-booking surfaces under `apps/`. It does **not** apply here. This service is multi-tenant by design.

---

## 1. Service one-liner

Rust + Axum API powering the sf-voice debugging product.

- **State store:** MySQL 8.4 (per CLAUDE.md rule 19). Local dev via `infra/dev/docker-compose.yml`; prod via `infra/deploy/docker-compose.mysql.yml`.
- **Embedded analytical + vector store:** DuckDB. Holds per-utterance embeddings and any per-call analytical rollups. In-process inside the API binary; file at `DUCKDB_PATH` (defaults to `./data/sf_voice.duckdb`). Uses the `vss` extension for HNSW vector indexes.
- **High-volume telemetry (future):** ClickHouse Cloud. Out of scope for v1.
- **Object storage:** S3. v1 reads only from internal/test buckets owned by sf-voice. Customer-bucket auth is deferred.
- **Voice models:** OpenAI Whisper (hosted) for ASR. Diarization model TBD. End-of-turn VAD from an internal service (see § 7).
- **Embedding model:** OpenAI `text-embedding-3-small` (1536 dims). Same API key as Whisper.

## 2. Multi-tenancy

Every queryable row carries `org_id`. Every API request resolves `org_id` from auth context (auth layer itself is v2 — v1 dev uses a fixed `org_id` from env). Every query filters by it. There is no global view of "all calls across all orgs" anywhere in v1.

## 3. v1 scope

- Schema migrations for `orgs`, `calls`, `files`, `transcripts`, `transcript_runs`, `jobs`, `prompt_slices` (MySQL) and `transcript_embeddings` (DuckDB).
- **Ingest job:** list S3 prefix → upsert `files` rows → for each new audio file, create or update a `calls` row → enqueue a `transcribe` job.
- **Transcribe job:** pull audio from S3 → call end-of-turn VAD service for segment boundaries → call Whisper per segment → call diarization → merge into utterances → write `transcript_runs` + per-utterance `transcripts` rows → embed each utterance via OpenAI → upsert into DuckDB `transcript_embeddings`.
- **Slice + prompt API:** create `prompt_slices` row → enqueue stub `sandbox` job that emits the seven canonical step events (and posts each to the org's Slack webhook) → set `prompt_slices.status` to `pr_open` with a placeholder URL when done.
- **Read APIs** for the timeline view: list calls; get call detail with utterances; get a job and tail its events via SSE.
- **Semantic search API:** `GET /api/search?q=...` runs the query string through the same embedding model, does nearest-neighbour against DuckDB, joins back to MySQL `transcripts` for the rows.

Out of scope: real sandbox provisioning, real PR creation, ClickHouse wiring, customer-bucket auth, multi-model embedding A/B.

## 4. Schema (MySQL 8.4)

The migration file is `migrations/0001_init.sql`. Authoritative DDL:

```sql
-- orgs: customer organizations
CREATE TABLE orgs (
  id                  BINARY(16) PRIMARY KEY,            -- uuid v7
  name                VARCHAR(255) NOT NULL,
  slug                VARCHAR(64)  NOT NULL UNIQUE,
  bucket_name         VARCHAR(255),
  bucket_prefix       VARCHAR(512),
  bucket_region       VARCHAR(32),
  bucket_role_arn     VARCHAR(512),                       -- reserved for v2 (cross-account assumption)
  bucket_external_id  VARCHAR(128),                       -- reserved for v2
  config_repo_url     VARCHAR(512),                       -- PR target
  slack_webhook_url   VARCHAR(512),                       -- per-org notifications
  created_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
                       ON UPDATE CURRENT_TIMESTAMP
);

-- calls: one row per phone call
CREATE TABLE calls (
  id                  BINARY(16) PRIMARY KEY,
  org_id              BINARY(16) NOT NULL,
  external_id         VARCHAR(255),                       -- telnyx / sf-voice runtime id
  started_at          TIMESTAMP NOT NULL,
  ended_at            TIMESTAMP NULL,
  duration_ms         INT NULL,
  caller_number       VARCHAR(32),                        -- e.164
  destination_number  VARCHAR(32),
  termination_reason  VARCHAR(64),
  audio_uri           VARCHAR(1024),                      -- mixed track if separated tracks unavailable
  caller_audio_uri    VARCHAR(1024),                      -- separated track
  ai_audio_uri        VARCHAR(1024),                      -- separated track
  created_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
                       ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (org_id) REFERENCES orgs(id),
  INDEX idx_calls_org_started (org_id, started_at DESC),
  INDEX idx_calls_external (org_id, external_id)
);

-- files: S3 objects we know about
CREATE TABLE files (
  id              BINARY(16) PRIMARY KEY,
  org_id          BINARY(16) NOT NULL,
  call_id         BINARY(16) NULL,                        -- nullable until linked
  bucket          VARCHAR(255) NOT NULL,
  s3_key          VARCHAR(1024) NOT NULL,
  byte_size       BIGINT,
  content_type    VARCHAR(64),
  etag            VARCHAR(64),                            -- change detection
  last_modified   TIMESTAMP NULL,                          -- from s3
  ingested_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (org_id)  REFERENCES orgs(id),
  FOREIGN KEY (call_id) REFERENCES calls(id),
  UNIQUE KEY uq_files_bucket_key (bucket, s3_key),
  INDEX idx_files_org_ingested (org_id, ingested_at DESC),
  INDEX idx_files_call (call_id)
);

-- transcript_runs: one row per (re-)transcription attempt; versioning
CREATE TABLE transcript_runs (
  id                 BINARY(16) PRIMARY KEY,
  call_id            BINARY(16) NOT NULL,
  status             ENUM('queued','running','done','failed') NOT NULL,
  whisper_model      VARCHAR(64),
  diarization_model  VARCHAR(64),
  vad_model          VARCHAR(64),
  triggered_by       VARCHAR(64) NOT NULL,                -- 'auto' | 'manual:<user_id>'
  error_message      TEXT,
  started_at         TIMESTAMP NULL,
  finished_at        TIMESTAMP NULL,
  created_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (call_id) REFERENCES calls(id),
  INDEX idx_runs_call_created (call_id, created_at DESC),
  INDEX idx_runs_status (status)
);

-- transcripts: one row per utterance/turn
CREATE TABLE transcripts (
  id             BIGINT PRIMARY KEY AUTO_INCREMENT,
  call_id        BINARY(16) NOT NULL,
  run_id         BINARY(16) NOT NULL,
  speaker_label  ENUM('ai','caller','unknown') NOT NULL,
  start_ms       INT NOT NULL,
  end_ms         INT NOT NULL,
  text           TEXT NOT NULL,
  confidence     FLOAT NULL,
  model_version  VARCHAR(64) NOT NULL,                    -- e.g. 'whisper-large-v3+pyannote-3.1'
  created_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (call_id) REFERENCES calls(id),
  FOREIGN KEY (run_id)  REFERENCES transcript_runs(id),
  INDEX idx_transcripts_call_start (call_id, start_ms),
  INDEX idx_transcripts_run (run_id),
  FULLTEXT KEY ftx_transcripts_text (text)
);

-- jobs: async work units (ingest, transcribe, sandbox, open_pr)
CREATE TABLE jobs (
  id               BINARY(16) PRIMARY KEY,
  org_id           BINARY(16) NOT NULL,
  kind             ENUM('ingest','transcribe','sandbox','open_pr') NOT NULL,
  subject_type     VARCHAR(32) NOT NULL,                  -- 'call' | 'file' | 'slice'
  subject_id       BINARY(16) NULL,
  status           ENUM('queued','running','done','failed','cancelled') NOT NULL,
  payload          JSON NULL,
  result           JSON NULL,
  error_message    TEXT,
  progress_steps   JSON NULL,                              -- [{step, status, ts, detail?}] for reasoning-path UI
  slack_thread_ts  VARCHAR(32),                            -- for threading subsequent posts
  created_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  started_at       TIMESTAMP NULL,
  finished_at      TIMESTAMP NULL,
  FOREIGN KEY (org_id) REFERENCES orgs(id),
  INDEX idx_jobs_status_kind (status, kind),
  INDEX idx_jobs_org_created (org_id, created_at DESC),
  INDEX idx_jobs_subject (subject_type, subject_id)
);

-- prompt_slices: 'select range, insert prompt' artifact
CREATE TABLE prompt_slices (
  id          BINARY(16) PRIMARY KEY,
  call_id     BINARY(16) NOT NULL,
  org_id      BINARY(16) NOT NULL,
  start_ms    INT NOT NULL,
  end_ms      INT NOT NULL,
  prompt_text TEXT NOT NULL,
  status      ENUM('draft','sandboxed','pr_open','merged','rejected') NOT NULL,
  job_id      BINARY(16) NULL,                            -- active sandbox job
  pr_url      VARCHAR(512),
  created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
               ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (call_id) REFERENCES calls(id),
  FOREIGN KEY (org_id)  REFERENCES orgs(id),
  FOREIGN KEY (job_id)  REFERENCES jobs(id),
  INDEX idx_slices_call (call_id),
  INDEX idx_slices_org_created (org_id, created_at DESC)
);
```

ID convention: tenant-visible PKs are `BINARY(16)` populated with UUID v7 (sortable by time, good for clustered-index inserts). High-volume internal rows (`transcripts`) use `BIGINT AUTO_INCREMENT`.

## 5. Vector embeddings (DuckDB)

Per-utterance embeddings live in DuckDB. The Rust API opens `DUCKDB_PATH` on startup and ensures the schema below exists. Two reasons we use DuckDB and not MySQL or a separate service:

1. It's already in the binary — no new service to deploy.
2. The `vss` extension gives us HNSW indexes with sub-millisecond k-NN at our scale.

```sql
-- run on startup, idempotent
INSTALL vss;
LOAD vss;

CREATE TABLE IF NOT EXISTS transcript_embeddings (
  transcript_id  BIGINT      NOT NULL,         -- fk-by-convention to mysql transcripts.id
  call_id        UUID        NOT NULL,
  org_id         UUID        NOT NULL,
  run_id         UUID        NOT NULL,         -- which transcript_runs.id produced the row
  model          VARCHAR     NOT NULL,         -- e.g. 'openai/text-embedding-3-small'
  embedding      FLOAT[1536] NOT NULL,
  text           VARCHAR     NOT NULL,         -- denormalized for fast preview; mysql remains source of truth
  created_at     TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (transcript_id, model)
);

-- hnsw index for cosine k-NN. m and ef_construction are duckdb-vss defaults.
CREATE INDEX IF NOT EXISTS idx_transcript_embeddings_hnsw
  ON transcript_embeddings
  USING HNSW (embedding)
  WITH (metric = 'cosine');

CREATE INDEX IF NOT EXISTS idx_transcript_embeddings_org
  ON transcript_embeddings (org_id);
```

**Why `transcript_id` is fk-by-convention.** DuckDB and MySQL don't share an FK enforcement boundary. The `transcribe` job is responsible for keeping these in sync: when it inserts a `transcripts` row it also inserts the matching `transcript_embeddings` row. When `transcript_runs.id` is replaced (re-transcribe), the job deletes old embedding rows for that `run_id` and writes new ones.

**Search.** `GET /api/search?q=...&limit=20` embeds `q` via the same OpenAI model, queries DuckDB:
```sql
SELECT transcript_id, call_id, text, array_cosine_distance(embedding, $1) AS dist
FROM transcript_embeddings
WHERE org_id = $2
ORDER BY dist
LIMIT $3;
```
then joins back to MySQL `transcripts` + `calls` to surface full context. The hnsw index makes this fast.

## 6. Analytics events (ClickHouse Cloud)

Out of scope for v1 schema work. The design assumes a future MergeTree table for high-cardinality per-event telemetry:

```
call_events (
  org_id          UUID,
  call_id         UUID,
  ts              DateTime64(6),
  event_type      LowCardinality(String),  -- 'vad_sample','llm_token','tts_chunk','tool_call','error'
  span_id         UUID,
  parent_span_id  UUID,
  duration_ms     Float64,
  payload         String                   -- JSON
)
ORDER BY (org_id, call_id, ts);
```

The timeline's VAD curve, LLM TTFT spans, and tool-call bars will read from there in phase 2. v1 timeline uses placeholder data synthesized from `transcripts` where possible.

## 7. Search use-cases mapped to schema

- **"When did AI interrupt caller"** — self-join `transcripts` (MySQL) on `call_id` where `speaker_label='ai'` overlaps a `speaker_label='caller'` row by `start_ms`/`end_ms`. Covered by `idx_transcripts_call_start`.

  ```sql
  SELECT a.call_id, a.start_ms
  FROM transcripts a
  JOIN transcripts b ON a.call_id = b.call_id
  WHERE a.speaker_label = 'ai'
    AND b.speaker_label = 'caller'
    AND a.start_ms BETWEEN b.start_ms AND b.end_ms;
  ```

- **"Why are customers dropping calls"** — semantic search over `transcript_embeddings` in DuckDB, filtered by `org_id`, often combined with `calls.termination_reason`. The query "customers giving up" embeds + finds the closest utterances; the joined `calls.termination_reason` separates real drops from completions. See § 5 for the SQL pattern.

- **Topic clustering** — `transcript_embeddings.embedding` is the input. v1 surface: ad-hoc DuckDB queries from notebooks. v2: a clustering job that writes a `cluster_id` back per transcript for filter UIs.

- **Keyword search across transcripts** — MySQL `MATCH(text) AGAINST(...)` on `transcripts.text` (FULLTEXT index). Cheaper than embeddings when the user types literal phrases.

- **"Calls that hit a latency threshold"** — phase 2. Needs `call_events` (ClickHouse) joined to `calls.org_id` (MySQL).

## 8. Pipeline contracts

- **End-of-turn VAD service.** Internal HTTP service. URL via env (`EOT_VAD_URL`). Accepts an audio chunk + VAD state; returns probability + `end_of_turn: bool`. Contract TBD before the transcribe job lands. **Reuse candidate:** `apps/ellie_ai/lib/ellie_ai/calls/vad_gate.ex` already implements turn-gating logic; v1 might expose that over HTTP rather than write a new Rust service. Decision pending.
- **Whisper.** OpenAI hosted, `whisper-large-v3` via `/v1/audio/transcriptions`. API key from `OPENAI_API_KEY`.
- **Diarization.** `pyannote-3.1` proposed (huggingface inference endpoint). URL via env (`DIARIZE_URL`). Confirm model and host before wiring.
- **Embeddings.** OpenAI `text-embedding-3-small` via `/v1/embeddings`. 1536 dims. Same `OPENAI_API_KEY`. Called once per utterance during the `transcribe` job (batched in groups of up to 100 per request).
- **Slack webhook.** URL per org from `orgs.slack_webhook_url`. Posted on every `jobs.progress_steps` append. First post stores `slack_thread_ts`; subsequent posts thread into it.

## 9. Routes (v1)

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

## 10. Implementation conventions

- **DB access — MySQL.** `sqlx` with `query!` / `query_as!` macros for compile-time-checked queries. `Pool<MySql>` lives in `AppState`.
- **DB access — DuckDB.** Single in-process `Connection` behind a mutex on `AppState`. Embeddings read/write happens in the transcribe job and the `/api/search` handler. Schema (incl. `vss` extension load) is created on startup if missing.
- **Job runner.** In-process tokio task that polls `jobs` table (`status='queued' ORDER BY created_at LIMIT 1 FOR UPDATE SKIP LOCKED`). Single worker in v1. Documented constraint: single API node.
- **Event broadcast.** In-process `tokio::sync::broadcast` registry keyed by `job_id`. Each job-step append publishes; SSE handlers subscribe. Single-node constraint same as runner.
- **UUIDs.** v7 from the `uuid` crate. Convert to/from `BINARY(16)` at the sqlx boundary; pass as DuckDB `UUID` natively.
- **Errors.** `AppError` enum with `IntoResponse`; never panic on a request path.
- **Tracing.** `tracing` + `tracing-subscriber`. Every job logs `job_id`, `org_id`, `kind` at every step.

## 11. Open questions for v2

- **Customer S3 auth.** IAM role assumption (recommended) vs stored access keys. Schema reserves the columns. Onboarding flow TBD.
- **Embedding store at scale.** DuckDB on a single node is fine through v1 (millions of rows, sub-second k-NN). When we cross node boundaries the options are ClickHouse vector indexes, pgvector, or a dedicated store. Driven by call volume.
- **Multi-model embeddings.** `transcript_embeddings.model` is part of the PK so multiple embedding versions can coexist for the same utterance. v1 stores only one model; v2 might A/B `text-embedding-3-small` vs `text-embedding-3-large` per org.
- **Speaker-identity mapping.** When tracks are mixed (no separated `caller_audio_uri` / `ai_audio_uri`), how do we label utterances? Loudest channel? Known TTS voiceprint? Telnyx side-tag? v1 falls back to `unknown`.
- **Real sandbox.** Spin up an actual instance of the customer's voice agent against a config branch and regenerate the slice's AI response.
- **Real PR creation.** GitHub App on the per-customer config repo; commit + open PR programmatically.
- **Live-watch.** Stream a call as it happens. Adds websockets and a hot-path event pipe.
- **Anomaly auto-detection.** Surface calls with slow turns / interrupts / dead air without the user filtering for them.
- **Cross-call dashboards.** p50 latency over time, week-over-week trends.

---

## Cross-references to the frontend

The frontend product spec lives at [`../frontend/AGENT.md`](../frontend/AGENT.md). Notable contract points the frontend depends on:

- SSE event payload from `GET /api/jobs/:id/events`: `{ step: string, status: "pending"|"running"|"done"|"failed", ts: iso8601, detail?: string }`.
- `progress_steps` is the same shape stored as JSON on `jobs`.
- The sandbox-stub job emits a fixed list of seven steps in order: `slice captured` → `context assembled` → `sandbox provisioned` → `regenerating AI response` → `rendering TTS audio` → `opening PR` → `awaiting review`.
- `prompt_slices.status` transitions `draft → sandboxed → pr_open` over the course of the sandbox job; the placeholder PR URL pattern is `https://github.com/sf-voice/cfg-<org.slug>/pull/0`.
