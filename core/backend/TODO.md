# core/backend — TODO

Carry-over from the YouTube ingest + knowledge-base planning session. Pick up tomorrow with the decisions list at the bottom.

---

## Where we are right now

Working end-to-end on `/admin/_internal/youtube`:

- yt-dlp + ffmpeg pipeline produces one parent doc (raw.mp4) + 3 derived docs (video.mp4, audio.m4a, audio.wav). All in `documents` table per migration `0006_documents.sql`. Self-referencing `source_id`, no ENUMs.
- Job walks `processing_status` queued → downloading → extracting → uploading → ready (or failed).
- yt-dlp stdout piped + parsed; `[download] xx.x%` throttled to 2s into `progress_steps.detail`.
- Step events stream via SSE at `/api/_internal/jobs/:id/events` (admin-gated). Frontend `EventSource` with cookie auth.
- "Re-ingest" button on terminal-state rows.
- Admin gate = `@sf-voice.sh` email suffix; popover-only entry (sidebar Admin link removed per Layout edit).
- Backend now on SeaORM (per recent MEMORY.md note "core/backend uses SeaORM 2.0 only, no sqlx in handlers"). Future code uses entity patterns; raw SQL only in `entities::apply_extras`.

---

## What we want to build next — knowledge base on top of the document tree

Six capabilities, in target order:

1. **Transcript with ms timestamps** per video. Whisper, segment-aligned.
2. **Search w/ timestamps** — both lexical (MySQL FULLTEXT) and semantic (vector k-NN). Return `{doc_id, start_ms, end_ms, text, score}`.
3. **Thumbnails** — ffmpeg single-frame extraction at 10% mark, uploaded as `image` document. Sprite grid for scrubbing is a polish item.
4. **Search modes**
   - Per-video summary ("what does this video talk about") — one-shot LLM at ingest, cached on `documents.summary_text`.
   - Cross-video topic search ("which video talks about X") — embed q → top-k segments globally → optional LLM synthesis with citations.
5. **Player + jump-to-timestamp** — HTML5 `<video>` + signed S3 URLs (5 min TTL, no new package; `aws-sdk-s3`'s `.presigned()` is in already). ffmpeg needs `-movflags +faststart` on the video.mp4 extraction.
6. **Saved searches as chat threads** — `search_threads` + `search_messages` tables. Citations as JSON on each assistant message. ChatGPT-style UI.

---

## Decisions made

- **Tenancy:** internal forever. No customer scope on any new tables.
- **Jobs:** separate + re-runnable. New job kinds: `transcribe_document`, `embed_document`, `thumbnail_document`, `summarize_document`. Each independently dispatchable.
- **Search scope:** global across all internal docs.
- **Organization:** both `documents.folder` (single VARCHAR, `/`-separated for hierarchy, e.g. `/internal/ml/3blue1brown`) + `documents.tags` (JSON array or `document_tags` join — TBD).
- **Signed URLs:** `aws-sdk-s3`'s built-in `.presigned()`. New admin endpoint that returns presigned URL for a doc id. 5 min TTL.
- **Search-result chunking:** sliding windows over Whisper segments — size ~3 segments (≈30s), stride 1 segment (≈10s), anchor on middle segment for jump-to. Standard time-coded RAG pattern.

## Decisions outstanding (answer these first thing tomorrow)

1. **Vector store: Qdrant vs DuckDB VSS.**
   - DuckDB VSS is wired already (`vss` extension loads at startup, `duckdb_schema::bootstrap`). Zero new infra. Fine through ~10M vectors.
   - Qdrant is a separate container (~$10/mo on DO). First-class payload filtering (tags/folders), scale ceiling ~50× higher.
   - My lean: **Qdrant** because payload filtering on tags/folder is exactly the query pattern, and "internal forever" doesn't mean "stays small forever". If you want fastest path to first results, DuckDB ships ~2 days sooner.
2. **LLM choice — confirmed "mix"?**
   - Claude Sonnet for summaries (better synthesis).
   - GPT-4o-mini for RAG answers (cheap, good enough).
   - OR: skip LLM entirely → no summaries, no synthesized answers; retrieval-only. Works but mediocre UX for "what does this video talk about". My lean: **mix**, since costs at internal scale are ~$20 total.
3. **Whisper hosted vs self-hosted.** OpenAI hosted is $0.006/min and zero ops; whisper.cpp is free but you maintain it. My lean: **hosted** for v1.
4. **Auto-tagging at ingest** — yes/no? I assume yes since you flagged tags as a real need.
5. **Folder model** — single VARCHAR with `/` hierarchy OR a normalized `folders` table? VARCHAR is simpler; table is queryable. My lean: **VARCHAR**.
6. **Inline vs separate jobs.** Already decided separate + re-runnable; just confirming the youtube_ingest job *enqueues* the downstream transcribe/embed/summarize jobs vs requiring manual trigger.
   - My lean: **auto-enqueue but each is independently re-runnable** — best of both.

---

## Phased plan (rough)

Each phase ships independently usable; we can stop after any phase if priorities shift.

### Phase 1 — Transcription (2-3 days)

- Migration: new `transcripts` shape that's document-scoped (extend the existing call-scoped table polymorphically with `subject_kind` + `subject_id`, OR add `document_id` alongside `call_id`). Decision in plan tomorrow.
- New job: `transcribe_document` — pulls `audio.wav` from S3 → OpenAI Whisper → INSERT per-segment rows with `start_ms`/`end_ms`.
- New endpoint: `GET /api/_internal/documents/:id/transcript`.
- Frontend: doc detail page shows the transcript as a clickable list.

### Phase 2 — Vector search (1-2 days)

- New job: `embed_document` — chunks transcript into sliding 3-segment windows, embeds each via `text-embedding-3-small` (1536d), writes to vector store (Qdrant or DuckDB depending on decision 1).
- New endpoint: `GET /api/_internal/search?q=…` — embeds q, k-NN, joins back to MySQL, returns ranked segments.
- Frontend: search box on the admin index; result rows link to player at timestamp.

### Phase 3 — Thumbnails + player (2 days)

- Extend `youtube_ingest` (or new `thumbnail_document` job) — ffmpeg extract single frame at 10% mark, upload as derived doc with `media_kind='image'`.
- Add `-movflags +faststart` to the video.mp4 extraction in `youtube_ingest` so seeking works without re-downloading.
- New endpoint: `GET /api/_internal/documents/:id/playback-url` — returns presigned URL.
- Frontend: `/admin/_internal/docs/:id` player page with HTML5 video + clickable transcript that calls `video.currentTime = ms/1000`.

### Phase 4 — Summaries + RAG answers (2 days)

- New columns on `documents`: `summary_text TEXT`, `summary_model VARCHAR`, `summary_updated_at TIMESTAMP`.
- New job: `summarize_document` — LLM call (Claude Sonnet) over full transcript, caches result. Auto-enqueued post-ingest; manually re-runnable.
- New endpoint: `POST /api/_internal/ask` — embed q → retrieve top-k=20 → group by doc → top 3-5 segments to LLM (GPT-4o-mini) → answer + citations `[{doc_id, start_ms, end_ms}]`.
- Frontend: question input on search page; answer card above the snippet results.

### Phase 5 — Chat threads (3 days)

- New tables: `search_threads(id, user_id, title, created_at)`, `search_messages(id, thread_id, role, content, citations JSON, created_at)`.
- Thread title auto-generated from first message via LLM, user-editable.
- Endpoints: `GET/POST /api/_internal/threads`, `GET/POST /api/_internal/threads/:id/messages`.
- Frontend: thread sidebar + message list + input. Citations in assistant messages are clickable → opens player at timestamp.

Total: **~2 weeks** of focused work.

---

## Reference notes

### Why sliding windows for chunking
- Single Whisper segments (5-10s): not enough context per vector → recall suffers.
- 3-segment windows (~30s) with 1-segment stride: same query gets 3 chances to match the right moment; each window still maps back to a precise timestamp via its middle segment's `start_ms`.
- Storage cost: ~3 vectors/min of video. Negligible at any scale we'd hit.

### DB comparison
| | DuckDB VSS | Qdrant | ClickHouse SH |
|---|---|---|---|
| New infra | No | 1 container | 1 container (heavier) |
| Already wired | Yes | No | No |
| Payload filter | Post-hoc MySQL join | First-class | SQL WHERE |
| Scale ceiling | ~10M vectors | 100M+ on one node | Billions |
| Cost on DO | $0 | ~$10/mo | ~$20/mo |
| Recommended | If shipping speed > clean filters | If filters/scale matter | Don't — overkill |

### Cost ballpark (internal-only, 200 videos × 30 min)
- Whisper: $0.006/min × 30min × 200 = **$36**
- Embeddings: ~negligible (text-embedding-3-small)
- Summaries (Claude Sonnet, one-shot per doc): ~$0.05 × 200 = **$10**
- RAG answers (GPT-4o-mini): ~$0.01/question × 1000 = **$10**
- **Total: ~$56** one-time + ~$0.01/question ongoing.

### Signed URL implementation sketch
```rust
use aws_sdk_s3::presigning::PresigningConfig;
let url = bucket.s3
    .get_object()
    .bucket(&bucket.bucket)
    .key(&doc.s3_key)
    .presigned(PresigningConfig::expires_in(Duration::from_secs(300))?)
    .await?
    .uri()
    .to_string();
```
No new crate. Returned to the frontend as JSON; the `<video>` element src-es it directly.

### SeaORM note
Since the recent sqlx → SeaORM port, all new code uses `entities::*` patterns. Raw SQL only allowed in `entities::apply_extras`. Apply this to every new migration's runtime-side code (`transcripts`, `search_threads`, etc.).


### Migrate to OAuth sign in + Magic link
