# core/backend/MEMORY.md

Decisions specific to `core/backend`.

Repo-wide conventions live in repo-root `AGENTS.md`. Product spec lives in [`AGENTS.md`](AGENTS.md).

Read this file before doing any work in `core/backend`.

---

## [2026-05-14] — Rust safety rules
**What was decided:**
- Avoid `unsafe { … }` blocks unless there's a documented reason (FFI,
  proven-safe transmute, performance-critical path with comments).
- Avoid `.unwrap()` and `.expect()` in production code paths. Use `?`,
  `match`, `unwrap_or`, `ok_or_else`, etc. Tests and one-shot scripts
  may use `.unwrap()` freely — failure there is the right behaviour.
- When `unsafe` or `unwrap` is justified, leave a one-line comment
  saying why so reviewers don't flag it.

**Why:** these are the two main escape hatches Rust gives you for "I
know better than the type system." When that's true it's fine; when
it's wrong the program panics or invokes UB. The default is to use
the type system, not bypass it.

**What was rejected:** a hard-no rule (would fight legitimate FFI use
in `core/backend/api/src/aws*.rs` and similar), and a "use `expect`
with a clear message" carve-out (still panics in prod).

---

## [2026-05-15] — youtube_ingest is resumable; retry ≠ re-ingest

**What was decided:**
- `work_dir` for `jobs/youtube_ingest.rs` is keyed by `document_id`
  (not `job_id`), at `/tmp/sf-voice-yt-{document_id}`. Cleaned up only on
  success; failure leaves it in place so the next retry can skip already-
  completed steps.
- Each step in `run_steps` is idempotent:
  - yt-dlp download → skipped if `raw.mp4` is on disk and non-empty.
  - ffmpeg extract (m4a / wav / video) → skipped per output file.
  - S3 upload → skipped per file if `head_object` succeeds on the key.
- Two distinct user-facing retry paths:
  1. **Soft retry** — `POST /api/_internal/documents/:id/retry`. Only
     valid when `processing_status='failed'`. Re-enqueues a new job
     against the same doc; does NOT delete derived rows or wipe parent
     `bucket`/`s3_key`. Idempotent step skipping resumes from where the
     job died.
  2. **Force re-ingest** — `POST /api/_internal/youtube { force: true }`.
     Deletes derived rows, resets the parent's fields, redownloads from
     scratch.
- Frontend exposes both buttons on failed rows: amber `Retry: {failed
  step}` (soft) + zinc `Re-ingest` (force). The step name is pulled from
  `progress_steps` — explicit `failed` event wins, else last `running`.

**Why:** without this, a failure during `uploading audio.m4a` after a
20-minute download forces redownloading the whole video. The
intermediate files are already on local disk and most uploads have
already landed in S3 — there's no reason to redo them. Soft retry
restarts the job *with* that context preserved; force is the escape
hatch for "actually start over."

**What was rejected:**
- Single retry that always force-redownloads — wastes bandwidth + time.
- Pure resume-only (no force button) — leaves no way out when an
  intermediate file is itself corrupt on disk.
- Branching inside the existing `create_youtube_ingest` handler — the
  retry semantics (preserve derived rows + parent fields) are different
  enough from the dedup/force semantics that a separate endpoint reads
  cleaner.
